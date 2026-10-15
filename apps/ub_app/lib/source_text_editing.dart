/// HTML textareas use LF even when an imported source retains CRLF or CR.
/// Keep that presentation separate from the exact source saved in the form.
String browserSourceInputText(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// A focus/selection update can echo the textarea's normalized line endings.
/// Only a substantive text edit replaces the original source representation.
String retainBrowserSourceText(String original, String input) =>
    input == browserSourceInputText(original) ? original : input;
