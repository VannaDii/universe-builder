//! Exact image bytes live in the transactional package; previews are disposable.
use super::*;
use base64::{engine::general_purpose::STANDARD, Engine as _};
use image::{ImageFormat, ImageReader};
use std::io::{Cursor, Read};
pub const MAX_IMAGE_BYTES: usize = 10 * 1_048_576;
pub(super) const IMAGE_CHUNK: usize = 256 * 1024;

fn decode(bytes: &[u8]) -> StoreResult<(image::DynamicImage, &'static str)> {
    if bytes.is_empty() || bytes.len() > MAX_IMAGE_BYTES {
        return Err(invalid("image must be between 1 byte and 10 MiB"));
    }
    let format = image::guess_format(bytes).map_err(|_| invalid("unrecognized image"))?;
    let media = match format {
        ImageFormat::Png => "image/png",
        ImageFormat::Jpeg => "image/jpeg",
        ImageFormat::WebP => "image/webp",
        _ => return Err(invalid("choose a PNG, JPEG or WebP image")),
    };
    let dimensions = ImageReader::with_format(Cursor::new(bytes), format)
        .into_dimensions()
        .map_err(|_| invalid("invalid image dimensions"))?;
    if dimensions.0 == 0
        || dimensions.1 == 0
        || dimensions.0 > 8192
        || dimensions.1 > 8192
        || u64::from(dimensions.0) * u64::from(dimensions.1) > 32_000_000
    {
        return Err(invalid(
            "image exceeds 8192 pixels per edge or 32 megapixels",
        ));
    }
    let mut reader = ImageReader::with_format(Cursor::new(bytes), format);
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(8192);
    limits.max_image_height = Some(8192);
    limits.max_alloc = Some(128 * 1_048_576);
    reader.limits(limits);
    Ok((
        reader
            .decode()
            .map_err(|_| invalid("image could not be decoded within limits"))?,
        media,
    ))
}
pub fn validate_image_metadata(asset: &ImageAsset) -> StoreResult<()> {
    if asset.digest.len() != 64
        || !asset
            .digest
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
        || asset.byte_size == 0
        || asset.byte_size > MAX_IMAGE_BYTES as u64
        || asset.width == 0
        || asset.height == 0
        || asset.width > 8192
        || asset.height > 8192
        || u64::from(asset.width) * u64::from(asset.height) > 32_000_000
        || !matches!(
            asset.media_type.as_str(),
            "image/png" | "image/jpeg" | "image/webp"
        )
        || asset.original_name.is_empty()
        || asset.original_name.len() > 255
        || asset.original_name.contains(['/', '\\'])
        || asset.original_name.chars().any(char::is_control)
    {
        return Err(invalid("invalid image metadata"));
    }
    Ok(())
}
pub(super) fn chunk_key(hash: &str, index: usize) -> String {
    format!("image-bytes:{hash}:{index}")
}
pub(super) fn image_bytes_from(c: &Connection, asset: &ImageAsset) -> StoreResult<Vec<u8>> {
    validate_image_metadata(asset)?;
    let mut bytes = Vec::with_capacity(asset.byte_size as usize);
    for index in 0..(asset.byte_size as usize).div_ceil(IMAGE_CHUNK) {
        let value = crate::workflow_storage::get(c, &chunk_key(&asset.digest, index))?
            .ok_or_else(|| invalid("missing image chunk"))?;
        let text = value
            .as_str()
            .ok_or_else(|| invalid("invalid image chunk"))?;
        if text.len() > IMAGE_CHUNK.div_ceil(3) * 4 {
            return Err(invalid("image chunk exceeds limit"));
        }
        let chunk = STANDARD
            .decode(text)
            .map_err(|_| invalid("invalid image encoding"))?;
        let expected = (asset.byte_size as usize - bytes.len()).min(IMAGE_CHUNK);
        if chunk.len() != expected {
            return Err(invalid("image chunk size mismatch"));
        }
        bytes.extend(chunk);
    }
    if hex::encode(Sha256::digest(&bytes)) != asset.digest {
        return Err(invalid("image digest mismatch"));
    }
    Ok(bytes)
}
pub(super) fn validate_image_bytes(asset: &ImageAsset, bytes: &[u8]) -> StoreResult<()> {
    validate_image_metadata(asset)?;
    let (decoded, media) = decode(bytes)?;
    if decoded.width() != asset.width
        || decoded.height() != asset.height
        || media != asset.media_type
        || bytes.len() as u64 != asset.byte_size
        || hex::encode(Sha256::digest(bytes)) != asset.digest
    {
        return Err(invalid("image metadata differs from original bytes"));
    }
    Ok(())
}
impl Kernel {
    pub fn stage_image(&mut self, source: &Path) -> StoreResult<(RecordId, ImageAsset)> {
        use std::os::unix::fs::OpenOptionsExt;
        let file = std::fs::OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
            .open(source)?;
        if !file.metadata()?.is_file() {
            return Err(invalid("choose a regular image file"));
        }
        let mut bytes = Vec::new();
        file.take(MAX_IMAGE_BYTES as u64 + 1)
            .read_to_end(&mut bytes)?;
        let (decoded, media) = decode(&bytes)?;
        let asset = ImageAsset {
            digest: hex::encode(Sha256::digest(&bytes)),
            media_type: media.into(),
            byte_size: bytes.len() as u64,
            width: decoded.width(),
            height: decoded.height(),
            original_name: source
                .file_name()
                .and_then(|s| s.to_str())
                .ok_or_else(|| invalid("image filename must be Unicode"))?
                .into(),
        };
        validate_image_metadata(&asset)?;
        let id = RecordId::generate(&mut rand::rng());
        let mut entries: Vec<_> = bytes
            .chunks(IMAGE_CHUNK)
            .enumerate()
            .map(|(i, b)| {
                (
                    chunk_key(&asset.digest, i),
                    Value::String(STANDARD.encode(b)),
                )
            })
            .collect();
        entries.push((
            format!("image-asset:{id}"),
            serde_json::to_value(Payload::ImageAsset(asset.clone()))
                .map_err(|_| invalid("image encoding"))?,
        ));
        self.workflow_put(&entries)?;
        Ok((id, asset))
    }
    pub fn image_bytes(&self, asset: &ImageAsset) -> StoreResult<Vec<u8>> {
        image_bytes_from(&self.conn, asset)
    }
    pub fn image_preview(&self, asset: &ImageAsset) -> StoreResult<String> {
        let bytes = self.image_bytes(asset)?;
        let (decoded, _) = decode(&bytes)?;
        for edge in [768, 512, 256] {
            let preview = decoded
                .thumbnail(edge.min(decoded.width()), edge.min(decoded.height()))
                .to_rgb8();
            let mut encoded = Vec::new();
            image::codecs::jpeg::JpegEncoder::new_with_quality(&mut encoded, 75)
                .encode_image(&preview)
                .map_err(|_| invalid("image preview encoding failed"))?;
            if encoded.len() <= 512 * 1024 {
                return Ok(format!(
                    "data:image/jpeg;base64,{}",
                    STANDARD.encode(encoded)
                ));
            }
        }
        Err(invalid("image preview exceeds limit"))
    }
}
