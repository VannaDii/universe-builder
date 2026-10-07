-- NORMATIVE UNRELEASED MODEL. One relational schema; not a production migration.

PRAGMA foreign_keys=ON;

CREATE TABLE "r_payload" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 37),
  v0 INTEGER REFERENCES "r_payload_v0"(__row_id),
  v1 INTEGER REFERENCES "r_payload_v1"(__row_id),
  v2 INTEGER REFERENCES "r_payload_v2"(__row_id),
  v3 INTEGER REFERENCES "r_payload_v3"(__row_id),
  v4 INTEGER REFERENCES "r_payload_v4"(__row_id),
  v5 INTEGER REFERENCES "r_payload_v5"(__row_id),
  v6 INTEGER REFERENCES "r_payload_v6"(__row_id),
  v7 INTEGER REFERENCES "r_payload_v7"(__row_id),
  v8 INTEGER REFERENCES "r_payload_v8"(__row_id),
  v9 INTEGER REFERENCES "r_payload_v9"(__row_id),
  v10 INTEGER REFERENCES "r_payload_v10"(__row_id),
  v11 INTEGER REFERENCES "r_payload_v11"(__row_id),
  v12 INTEGER REFERENCES "r_payload_v12"(__row_id),
  v13 INTEGER REFERENCES "r_payload_v13"(__row_id),
  v14 INTEGER REFERENCES "r_payload_v14"(__row_id),
  v15 INTEGER REFERENCES "r_payload_v15"(__row_id),
  v16 INTEGER REFERENCES "r_payload_v16"(__row_id),
  v17 INTEGER REFERENCES "r_payload_v17"(__row_id),
  v18 INTEGER REFERENCES "r_payload_v18"(__row_id),
  v19 INTEGER REFERENCES "r_payload_v19"(__row_id),
  v20 INTEGER REFERENCES "r_payload_v20"(__row_id),
  v21 INTEGER REFERENCES "r_payload_v21"(__row_id),
  v22 INTEGER REFERENCES "r_payload_v22"(__row_id),
  v23 INTEGER REFERENCES "r_payload_v23"(__row_id),
  v24 INTEGER REFERENCES "r_payload_v24"(__row_id),
  v25 INTEGER REFERENCES "r_payload_v25"(__row_id),
  v26 INTEGER REFERENCES "r_payload_v26"(__row_id),
  v27 INTEGER REFERENCES "r_payload_v27"(__row_id),
  v28 INTEGER REFERENCES "r_payload_v28"(__row_id),
  v29 INTEGER REFERENCES "r_payload_v29"(__row_id),
  v30 INTEGER REFERENCES "r_payload_v30"(__row_id),
  v31 INTEGER REFERENCES "r_payload_v31"(__row_id),
  v32 INTEGER REFERENCES "r_payload_v32"(__row_id),
  v33 INTEGER REFERENCES "r_payload_v33"(__row_id),
  v34 INTEGER REFERENCES "r_payload_v34"(__row_id),
  v35 INTEGER REFERENCES "r_payload_v35"(__row_id),
  v36 INTEGER REFERENCES "r_payload_v36"(__row_id),
  v37 INTEGER REFERENCES "r_payload_v37"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL),
  CHECK(variant=6 OR v6 IS NULL),
  CHECK(variant!=6 OR v6 IS NOT NULL),
  CHECK(variant=7 OR v7 IS NULL),
  CHECK(variant!=7 OR v7 IS NOT NULL),
  CHECK(variant=8 OR v8 IS NULL),
  CHECK(variant!=8 OR v8 IS NOT NULL),
  CHECK(variant=9 OR v9 IS NULL),
  CHECK(variant!=9 OR v9 IS NOT NULL),
  CHECK(variant=10 OR v10 IS NULL),
  CHECK(variant!=10 OR v10 IS NOT NULL),
  CHECK(variant=11 OR v11 IS NULL),
  CHECK(variant!=11 OR v11 IS NOT NULL),
  CHECK(variant=12 OR v12 IS NULL),
  CHECK(variant!=12 OR v12 IS NOT NULL),
  CHECK(variant=13 OR v13 IS NULL),
  CHECK(variant!=13 OR v13 IS NOT NULL),
  CHECK(variant=14 OR v14 IS NULL),
  CHECK(variant!=14 OR v14 IS NOT NULL),
  CHECK(variant=15 OR v15 IS NULL),
  CHECK(variant!=15 OR v15 IS NOT NULL),
  CHECK(variant=16 OR v16 IS NULL),
  CHECK(variant!=16 OR v16 IS NOT NULL),
  CHECK(variant=17 OR v17 IS NULL),
  CHECK(variant!=17 OR v17 IS NOT NULL),
  CHECK(variant=18 OR v18 IS NULL),
  CHECK(variant!=18 OR v18 IS NOT NULL),
  CHECK(variant=19 OR v19 IS NULL),
  CHECK(variant!=19 OR v19 IS NOT NULL),
  CHECK(variant=20 OR v20 IS NULL),
  CHECK(variant!=20 OR v20 IS NOT NULL),
  CHECK(variant=21 OR v21 IS NULL),
  CHECK(variant!=21 OR v21 IS NOT NULL),
  CHECK(variant=22 OR v22 IS NULL),
  CHECK(variant!=22 OR v22 IS NOT NULL),
  CHECK(variant=23 OR v23 IS NULL),
  CHECK(variant!=23 OR v23 IS NOT NULL),
  CHECK(variant=24 OR v24 IS NULL),
  CHECK(variant!=24 OR v24 IS NOT NULL),
  CHECK(variant=25 OR v25 IS NULL),
  CHECK(variant!=25 OR v25 IS NOT NULL),
  CHECK(variant=26 OR v26 IS NULL),
  CHECK(variant!=26 OR v26 IS NOT NULL),
  CHECK(variant=27 OR v27 IS NULL),
  CHECK(variant!=27 OR v27 IS NOT NULL),
  CHECK(variant=28 OR v28 IS NULL),
  CHECK(variant!=28 OR v28 IS NOT NULL),
  CHECK(variant=29 OR v29 IS NULL),
  CHECK(variant!=29 OR v29 IS NOT NULL),
  CHECK(variant=30 OR v30 IS NULL),
  CHECK(variant!=30 OR v30 IS NOT NULL),
  CHECK(variant=31 OR v31 IS NULL),
  CHECK(variant!=31 OR v31 IS NOT NULL),
  CHECK(variant=32 OR v32 IS NULL),
  CHECK(variant!=32 OR v32 IS NOT NULL),
  CHECK(variant=33 OR v33 IS NULL),
  CHECK(variant!=33 OR v33 IS NOT NULL),
  CHECK(variant=34 OR v34 IS NULL),
  CHECK(variant!=34 OR v34 IS NOT NULL),
  CHECK(variant=35 OR v35 IS NULL),
  CHECK(variant!=35 OR v35 IS NOT NULL),
  CHECK(variant=36 OR v36 IS NULL),
  CHECK(variant!=36 OR v36 IS NOT NULL),
  CHECK(variant=37 OR v37 IS NULL),
  CHECK(variant!=37 OR v37 IS NOT NULL)
) STRICT;

CREATE TABLE "r_payload_v0" (
  __row_id INTEGER PRIMARY KEY,
  "names__state" INTEGER NOT NULL CHECK("names__state" IN (2)),
  "names" INTEGER REFERENCES "r_payload_v0_names"(__row_id),
  "classification__state" INTEGER NOT NULL CHECK("classification__state" IN (0,1,2)),
  "classification" INTEGER REFERENCES "r_payload_v0_classification"(__row_id),
  "classificationResolution__state" INTEGER NOT NULL CHECK("classificationResolution__state" IN (2)),
  "classificationResolution" TEXT,
  "worldAssociations__state" INTEGER NOT NULL CHECK("worldAssociations__state" IN (2)),
  "worldAssociations" INTEGER REFERENCES "r_payload_v0_world_associations"(__row_id),
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v0_labels"(__row_id),
  "metadata__state" INTEGER NOT NULL CHECK("metadata__state" IN (2)),
  "metadata" INTEGER REFERENCES "r_payload_v0_metadata"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("names__state"=2 AND "names" IS NOT NULL) OR ("names__state" IN (0,1) AND "names" IS NULL)),
  CHECK(("classification__state"=2 AND "classification" IS NOT NULL) OR ("classification__state" IN (0,1) AND "classification" IS NULL)),
  CHECK(("classificationResolution__state"=2 AND "classificationResolution" IS NOT NULL) OR ("classificationResolution__state" IN (0,1) AND "classificationResolution" IS NULL)),
  CHECK("classificationResolution" IN ('unclassified','resolved','ambiguous')),
  CHECK(("worldAssociations__state"=2 AND "worldAssociations" IS NOT NULL) OR ("worldAssociations__state" IN (0,1) AND "worldAssociations" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("metadata__state"=2 AND "metadata" IS NOT NULL) OR ("metadata__state" IN (0,1) AND "metadata" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='entity')
) STRICT;

CREATE TABLE "r_payload_v0_names" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v0_names_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v0_names"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_contextual_name"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_contextual_name" (
  __row_id INTEGER PRIMARY KEY,
  "text__state" INTEGER NOT NULL CHECK("text__state" IN (2)),
  "text" TEXT,
  "language__state" INTEGER NOT NULL CHECK("language__state" IN (0,1,2)),
  "language" INTEGER REFERENCES "r_contextual_name_language"(__row_id),
  "community__state" INTEGER NOT NULL CHECK("community__state" IN (0,1,2)),
  "community" INTEGER REFERENCES "r_contextual_name_community"(__row_id),
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (0,1,2)),
  "role" INTEGER REFERENCES "r_contextual_name_role"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  CHECK(("text__state"=2 AND "text" IS NOT NULL) OR ("text__state" IN (0,1) AND "text" IS NULL)),
  CHECK(("language__state"=2 AND "language" IS NOT NULL) OR ("language__state" IN (0,1) AND "language" IS NULL)),
  CHECK(("community__state"=2 AND "community" IS NOT NULL) OR ("community__state" IN (0,1) AND "community" IS NULL)),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL))
) STRICT;

CREATE TABLE "r_contextual_name_language" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_contextual_name_community" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_contextual_name_role" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_validity" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 6),
  v0 INTEGER REFERENCES "r_validity_v0"(__row_id),
  v1 INTEGER REFERENCES "r_validity_v1"(__row_id),
  v2 INTEGER REFERENCES "r_validity_v2"(__row_id),
  v3 INTEGER REFERENCES "r_validity_v3"(__row_id),
  v4 INTEGER REFERENCES "r_validity_v4"(__row_id),
  v5 INTEGER REFERENCES "r_validity_v5"(__row_id),
  v6 INTEGER REFERENCES "r_validity_v6"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL),
  CHECK(variant=6 OR v6 IS NULL),
  CHECK(variant!=6 OR v6 IS NOT NULL)
) STRICT;

CREATE TABLE "r_validity_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unspecified')
) STRICT;

CREATE TABLE "r_validity_v1" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unknown')
) STRICT;

CREATE TABLE "r_validity_v2" (
  __row_id INTEGER PRIMARY KEY,
  "at__state" INTEGER NOT NULL CHECK("at__state" IN (2)),
  "at" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("at__state"=2 AND "at" IS NOT NULL) OR ("at__state" IN (0,1) AND "at" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='instant')
) STRICT;

CREATE TABLE "r_temporal_expression" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 5),
  v0 INTEGER REFERENCES "r_temporal_expression_v0"(__row_id),
  v1 INTEGER REFERENCES "r_temporal_expression_v1"(__row_id),
  v2 INTEGER REFERENCES "r_temporal_expression_v2"(__row_id),
  v3 INTEGER REFERENCES "r_temporal_expression_v3"(__row_id),
  v4 INTEGER REFERENCES "r_temporal_expression_v4"(__row_id),
  v5 INTEGER REFERENCES "r_temporal_expression_v5"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL)
) STRICT;

CREATE TABLE "r_temporal_expression_v0" (
  __row_id INTEGER PRIMARY KEY,
  "calendar__state" INTEGER NOT NULL CHECK("calendar__state" IN (2)),
  "calendar" TEXT,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("calendar__state"=2 AND "calendar" IS NOT NULL) OR ("calendar__state" IN (0,1) AND "calendar" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='exact')
) STRICT;

CREATE TABLE "r_temporal_expression_v1" (
  __row_id INTEGER PRIMARY KEY,
  "calendar__state" INTEGER NOT NULL CHECK("calendar__state" IN (2)),
  "calendar" TEXT,
  "start__state" INTEGER NOT NULL CHECK("start__state" IN (2)),
  "start" INTEGER REFERENCES "r_temporal_bound"(__row_id),
  "end__state" INTEGER NOT NULL CHECK("end__state" IN (2)),
  "end" INTEGER REFERENCES "r_temporal_bound"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("calendar__state"=2 AND "calendar" IS NOT NULL) OR ("calendar__state" IN (0,1) AND "calendar" IS NULL)),
  CHECK(("start__state"=2 AND "start" IS NOT NULL) OR ("start__state" IN (0,1) AND "start" IS NULL)),
  CHECK(("end__state"=2 AND "end" IS NOT NULL) OR ("end__state" IN (0,1) AND "end" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='interval')
) STRICT;

CREATE TABLE "r_temporal_bound" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 4),
  v0 INTEGER REFERENCES "r_temporal_bound_v0"(__row_id),
  v1 INTEGER REFERENCES "r_temporal_bound_v1"(__row_id),
  v2 INTEGER REFERENCES "r_temporal_bound_v2"(__row_id),
  v3 INTEGER REFERENCES "r_temporal_bound_v3"(__row_id),
  v4 INTEGER REFERENCES "r_temporal_bound_v4"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL)
) STRICT;

CREATE TABLE "r_temporal_bound_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unbounded')
) STRICT;

CREATE TABLE "r_temporal_bound_v1" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unknown')
) STRICT;

CREATE TABLE "r_temporal_bound_v2" (
  __row_id INTEGER PRIMARY KEY,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='exact')
) STRICT;

CREATE TABLE "r_temporal_bound_v3" (
  __row_id INTEGER PRIMARY KEY,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" TEXT,
  "uncertainty__state" INTEGER NOT NULL CHECK("uncertainty__state" IN (2)),
  "uncertainty" INTEGER REFERENCES "r_value"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("uncertainty__state"=2 AND "uncertainty" IS NOT NULL) OR ("uncertainty__state" IN (0,1) AND "uncertainty" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='approximate')
) STRICT;

CREATE TABLE "r_value" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 15),
  v0 INTEGER REFERENCES "r_value_v0"(__row_id),
  v1 INTEGER REFERENCES "r_value_v1"(__row_id),
  v2 INTEGER REFERENCES "r_value_v2"(__row_id),
  v3 INTEGER REFERENCES "r_value_v3"(__row_id),
  v4 INTEGER REFERENCES "r_value_v4"(__row_id),
  v5 INTEGER REFERENCES "r_value_v5"(__row_id),
  v6 INTEGER REFERENCES "r_value_v6"(__row_id),
  v7 INTEGER REFERENCES "r_value_v7"(__row_id),
  v8 INTEGER REFERENCES "r_value_v8"(__row_id),
  v9 INTEGER REFERENCES "r_value_v9"(__row_id),
  v10 INTEGER REFERENCES "r_value_v10"(__row_id),
  v11 INTEGER REFERENCES "r_value_v11"(__row_id),
  v12 INTEGER REFERENCES "r_value_v12"(__row_id),
  v13 INTEGER REFERENCES "r_value_v13"(__row_id),
  v14 INTEGER REFERENCES "r_value_v14"(__row_id),
  v15 INTEGER REFERENCES "r_value_v15"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL),
  CHECK(variant=6 OR v6 IS NULL),
  CHECK(variant!=6 OR v6 IS NOT NULL),
  CHECK(variant=7 OR v7 IS NULL),
  CHECK(variant!=7 OR v7 IS NOT NULL),
  CHECK(variant=8 OR v8 IS NULL),
  CHECK(variant!=8 OR v8 IS NOT NULL),
  CHECK(variant=9 OR v9 IS NULL),
  CHECK(variant!=9 OR v9 IS NOT NULL),
  CHECK(variant=10 OR v10 IS NULL),
  CHECK(variant!=10 OR v10 IS NOT NULL),
  CHECK(variant=11 OR v11 IS NULL),
  CHECK(variant!=11 OR v11 IS NOT NULL),
  CHECK(variant=12 OR v12 IS NULL),
  CHECK(variant!=12 OR v12 IS NOT NULL),
  CHECK(variant=13 OR v13 IS NULL),
  CHECK(variant!=13 OR v13 IS NOT NULL),
  CHECK(variant=14 OR v14 IS NULL),
  CHECK(variant!=14 OR v14 IS NOT NULL),
  CHECK(variant=15 OR v15 IS NULL),
  CHECK(variant!=15 OR v15 IS NOT NULL)
) STRICT;

CREATE TABLE "r_value_v0" (
  __row_id INTEGER PRIMARY KEY,
  "text__state" INTEGER NOT NULL CHECK("text__state" IN (2)),
  "text" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("text__state"=2 AND "text" IS NOT NULL) OR ("text__state" IN (0,1) AND "text" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='text')
) STRICT;

CREATE TABLE "r_value_v1" (
  __row_id INTEGER PRIMARY KEY,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK("value" IN (0,1)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='boolean')
) STRICT;

CREATE TABLE "r_value_v2" (
  __row_id INTEGER PRIMARY KEY,
  "digits__state" INTEGER NOT NULL CHECK("digits__state" IN (2)),
  "digits" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("digits__state"=2 AND "digits" IS NOT NULL) OR ("digits__state" IN (0,1) AND "digits" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='integer')
) STRICT;

CREATE TABLE "r_value_v3" (
  __row_id INTEGER PRIMARY KEY,
  "digits__state" INTEGER NOT NULL CHECK("digits__state" IN (2)),
  "digits" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("digits__state"=2 AND "digits" IS NOT NULL) OR ("digits__state" IN (0,1) AND "digits" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='decimal')
) STRICT;

CREATE TABLE "r_value_v4" (
  __row_id INTEGER PRIMARY KEY,
  "numerator__state" INTEGER NOT NULL CHECK("numerator__state" IN (2)),
  "numerator" TEXT,
  "denominator__state" INTEGER NOT NULL CHECK("denominator__state" IN (2)),
  "denominator" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("numerator__state"=2 AND "numerator" IS NOT NULL) OR ("numerator__state" IN (0,1) AND "numerator" IS NULL)),
  CHECK(("denominator__state"=2 AND "denominator" IS NOT NULL) OR ("denominator__state" IN (0,1) AND "denominator" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='rational')
) STRICT;

CREATE TABLE "r_value_v5" (
  __row_id INTEGER PRIMARY KEY,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  "unit__state" INTEGER NOT NULL CHECK("unit__state" IN (2)),
  "unit" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("unit__state"=2 AND "unit" IS NOT NULL) OR ("unit__state" IN (0,1) AND "unit" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='quantity')
) STRICT;

CREATE TABLE "r_value_v6" (
  __row_id INTEGER PRIMARY KEY,
  "lower__state" INTEGER NOT NULL CHECK("lower__state" IN (2)),
  "lower" INTEGER REFERENCES "r_value"(__row_id),
  "upper__state" INTEGER NOT NULL CHECK("upper__state" IN (2)),
  "upper" INTEGER REFERENCES "r_value"(__row_id),
  "lower_inclusive__state" INTEGER NOT NULL CHECK("lower_inclusive__state" IN (2)),
  "lower_inclusive" INTEGER,
  "upper_inclusive__state" INTEGER NOT NULL CHECK("upper_inclusive__state" IN (2)),
  "upper_inclusive" INTEGER,
  "unit__state" INTEGER NOT NULL CHECK("unit__state" IN (0,1,2)),
  "unit" INTEGER REFERENCES "r_value_v6_unit"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("lower__state"=2 AND "lower" IS NOT NULL) OR ("lower__state" IN (0,1) AND "lower" IS NULL)),
  CHECK(("upper__state"=2 AND "upper" IS NOT NULL) OR ("upper__state" IN (0,1) AND "upper" IS NULL)),
  CHECK(("lower_inclusive__state"=2 AND "lower_inclusive" IS NOT NULL) OR ("lower_inclusive__state" IN (0,1) AND "lower_inclusive" IS NULL)),
  CHECK("lower_inclusive" IN (0,1)),
  CHECK(("upper_inclusive__state"=2 AND "upper_inclusive" IS NOT NULL) OR ("upper_inclusive__state" IN (0,1) AND "upper_inclusive" IS NULL)),
  CHECK("upper_inclusive" IN (0,1)),
  CHECK(("unit__state"=2 AND "unit" IS NOT NULL) OR ("unit__state" IN (0,1) AND "unit" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='range')
) STRICT;

CREATE TABLE "r_value_v6_unit" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_value_v7" (
  __row_id INTEGER PRIMARY KEY,
  "ref__state" INTEGER NOT NULL CHECK("ref__state" IN (2)),
  "ref" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("ref__state"=2 AND "ref" IS NOT NULL) OR ("ref__state" IN (0,1) AND "ref" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='entity_ref')
) STRICT;

CREATE TABLE "r_record_ref" (
  __row_id INTEGER PRIMARY KEY,
  "universe__state" INTEGER NOT NULL CHECK("universe__state" IN (0,1,2)),
  "universe" INTEGER REFERENCES "r_record_ref_universe"(__row_id),
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" TEXT,
  CHECK(("universe__state"=2 AND "universe" IS NOT NULL) OR ("universe__state" IN (0,1) AND "universe" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL))
) STRICT;

CREATE TABLE "r_record_ref_universe" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_value_v8" (
  __row_id INTEGER PRIMARY KEY,
  "ref__state" INTEGER NOT NULL CHECK("ref__state" IN (2)),
  "ref" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("ref__state"=2 AND "ref" IS NOT NULL) OR ("ref__state" IN (0,1) AND "ref" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_ref')
) STRICT;

CREATE TABLE "r_value_v9" (
  __row_id INTEGER PRIMARY KEY,
  "ref__state" INTEGER NOT NULL CHECK("ref__state" IN (2)),
  "ref" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("ref__state"=2 AND "ref" IS NOT NULL) OR ("ref__state" IN (0,1) AND "ref" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='proposition_ref')
) STRICT;

CREATE TABLE "r_value_v10" (
  __row_id INTEGER PRIMARY KEY,
  "temporal__state" INTEGER NOT NULL CHECK("temporal__state" IN (2)),
  "temporal" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("temporal__state"=2 AND "temporal" IS NOT NULL) OR ("temporal__state" IN (0,1) AND "temporal" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='temporal')
) STRICT;

CREATE TABLE "r_value_v11" (
  __row_id INTEGER PRIMARY KEY,
  "spatial__state" INTEGER NOT NULL CHECK("spatial__state" IN (2)),
  "spatial" INTEGER REFERENCES "r_spatial_expression"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("spatial__state"=2 AND "spatial" IS NOT NULL) OR ("spatial__state" IN (0,1) AND "spatial" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='spatial')
) STRICT;

CREATE TABLE "r_spatial_expression" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 5),
  v0 INTEGER REFERENCES "r_spatial_expression_v0"(__row_id),
  v1 INTEGER REFERENCES "r_spatial_expression_v1"(__row_id),
  v2 INTEGER REFERENCES "r_spatial_expression_v2"(__row_id),
  v3 INTEGER REFERENCES "r_spatial_expression_v3"(__row_id),
  v4 INTEGER REFERENCES "r_spatial_expression_v4"(__row_id),
  v5 INTEGER REFERENCES "r_spatial_expression_v5"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL)
) STRICT;

CREATE TABLE "r_spatial_expression_v0" (
  __row_id INTEGER PRIMARY KEY,
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='contained_in')
) STRICT;

CREATE TABLE "r_spatial_expression_v1" (
  __row_id INTEGER PRIMARY KEY,
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='adjacent_to')
) STRICT;

CREATE TABLE "r_spatial_expression_v2" (
  __row_id INTEGER PRIMARY KEY,
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='connected_to')
) STRICT;

CREATE TABLE "r_spatial_expression_v3" (
  __row_id INTEGER PRIMARY KEY,
  "reference__state" INTEGER NOT NULL CHECK("reference__state" IN (2)),
  "reference" TEXT,
  "values__state" INTEGER NOT NULL CHECK("values__state" IN (2)),
  "values" INTEGER REFERENCES "r_spatial_expression_v3_values"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("reference__state"=2 AND "reference" IS NOT NULL) OR ("reference__state" IN (0,1) AND "reference" IS NULL)),
  CHECK(("values__state"=2 AND "values" IS NOT NULL) OR ("values__state" IN (0,1) AND "values" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='coordinates')
) STRICT;

CREATE TABLE "r_spatial_expression_v3_values" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_spatial_expression_v3_values_items" (owner INTEGER NOT NULL REFERENCES "r_spatial_expression_v3_values"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_spatial_expression_v4" (
  __row_id INTEGER PRIMARY KEY,
  "from__state" INTEGER NOT NULL CHECK("from__state" IN (2)),
  "from" INTEGER REFERENCES "r_record_ref"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  "unit__state" INTEGER NOT NULL CHECK("unit__state" IN (2)),
  "unit" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("from__state"=2 AND "from" IS NOT NULL) OR ("from__state" IN (0,1) AND "from" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("unit__state"=2 AND "unit" IS NOT NULL) OR ("unit__state" IN (0,1) AND "unit" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='distance')
) STRICT;

CREATE TABLE "r_spatial_expression_v5" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unspecified')
) STRICT;

CREATE TABLE "r_value_v12" (
  __row_id INTEGER PRIMARY KEY,
  "definition__state" INTEGER NOT NULL CHECK("definition__state" IN (2)),
  "definition" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("definition__state"=2 AND "definition" IS NOT NULL) OR ("definition__state" IN (0,1) AND "definition" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='enum')
) STRICT;

CREATE TABLE "r_value_v13" (
  __row_id INTEGER PRIMARY KEY,
  "items__state" INTEGER NOT NULL CHECK("items__state" IN (2)),
  "items" INTEGER REFERENCES "r_value_v13_items"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("items__state"=2 AND "items" IS NOT NULL) OR ("items__state" IN (0,1) AND "items" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='sequence')
) STRICT;

CREATE TABLE "r_value_v13_items" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_value_v13_items_items" (owner INTEGER NOT NULL REFERENCES "r_value_v13_items"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_value_v14" (
  __row_id INTEGER PRIMARY KEY,
  "items__state" INTEGER NOT NULL CHECK("items__state" IN (2)),
  "items" INTEGER REFERENCES "r_value_v14_items"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("items__state"=2 AND "items" IS NOT NULL) OR ("items__state" IN (0,1) AND "items" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='set')
) STRICT;

CREATE TABLE "r_value_v14_items" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_value_v14_items_items" (owner INTEGER NOT NULL REFERENCES "r_value_v14_items"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_value_v15" (
  __row_id INTEGER PRIMARY KEY,
  "definition__state" INTEGER NOT NULL CHECK("definition__state" IN (2)),
  "definition" TEXT,
  "fields__state" INTEGER NOT NULL CHECK("fields__state" IN (2)),
  "fields" INTEGER REFERENCES "r_value_v15_fields"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("definition__state"=2 AND "definition" IS NOT NULL) OR ("definition__state" IN (0,1) AND "definition" IS NULL)),
  CHECK(("fields__state"=2 AND "fields" IS NOT NULL) OR ("fields__state" IN (0,1) AND "fields" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='structured')
) STRICT;

CREATE TABLE "r_value_v15_fields" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_value_v15_fields_items" (owner INTEGER NOT NULL REFERENCES "r_value_v15_fields"(__row_id), name TEXT NOT NULL, item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_temporal_bound_v4" (
  __row_id INTEGER PRIMARY KEY,
  "lower__state" INTEGER NOT NULL CHECK("lower__state" IN (2)),
  "lower" TEXT,
  "upper__state" INTEGER NOT NULL CHECK("upper__state" IN (2)),
  "upper" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("lower__state"=2 AND "lower" IS NOT NULL) OR ("lower__state" IN (0,1) AND "lower" IS NULL)),
  CHECK(("upper__state"=2 AND "upper" IS NOT NULL) OR ("upper__state" IN (0,1) AND "upper" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='bounded_uncertainty')
) STRICT;

CREATE TABLE "r_temporal_expression_v2" (
  __row_id INTEGER PRIMARY KEY,
  "calendar__state" INTEGER NOT NULL CHECK("calendar__state" IN (2)),
  "calendar" TEXT,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" TEXT,
  "uncertainty__state" INTEGER NOT NULL CHECK("uncertainty__state" IN (2)),
  "uncertainty" INTEGER REFERENCES "r_value"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("calendar__state"=2 AND "calendar" IS NOT NULL) OR ("calendar__state" IN (0,1) AND "calendar" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("uncertainty__state"=2 AND "uncertainty" IS NOT NULL) OR ("uncertainty__state" IN (0,1) AND "uncertainty" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='approximate')
) STRICT;

CREATE TABLE "r_temporal_expression_v3" (
  __row_id INTEGER PRIMARY KEY,
  "calendar__state" INTEGER NOT NULL CHECK("calendar__state" IN (2)),
  "calendar" TEXT,
  "amount__state" INTEGER NOT NULL CHECK("amount__state" IN (2)),
  "amount" INTEGER REFERENCES "r_value"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("calendar__state"=2 AND "calendar" IS NOT NULL) OR ("calendar__state" IN (0,1) AND "calendar" IS NULL)),
  CHECK(("amount__state"=2 AND "amount" IS NOT NULL) OR ("amount__state" IN (0,1) AND "amount" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='duration')
) STRICT;

CREATE TABLE "r_temporal_expression_v4" (
  __row_id INTEGER PRIMARY KEY,
  "calendar__state" INTEGER NOT NULL CHECK("calendar__state" IN (2)),
  "calendar" TEXT,
  "relation__state" INTEGER NOT NULL CHECK("relation__state" IN (2)),
  "relation" INTEGER REFERENCES "r_temporal_relation"(__row_id),
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("calendar__state"=2 AND "calendar" IS NOT NULL) OR ("calendar__state" IN (0,1) AND "calendar" IS NULL)),
  CHECK(("relation__state"=2 AND "relation" IS NOT NULL) OR ("relation__state" IN (0,1) AND "relation" IS NULL)),
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='relative')
) STRICT;

CREATE TABLE "r_temporal_relation" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 4),
  v0 TEXT,
  v1 TEXT,
  v2 TEXT,
  v3 TEXT,
  v4 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL)
) STRICT;

CREATE TABLE "r_temporal_expression_v5" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unspecified')
) STRICT;

CREATE TABLE "r_validity_v3" (
  __row_id INTEGER PRIMARY KEY,
  "start__state" INTEGER NOT NULL CHECK("start__state" IN (2)),
  "start" INTEGER REFERENCES "r_temporal_bound"(__row_id),
  "end__state" INTEGER NOT NULL CHECK("end__state" IN (2)),
  "end" INTEGER REFERENCES "r_temporal_bound"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("start__state"=2 AND "start" IS NOT NULL) OR ("start__state" IN (0,1) AND "start" IS NULL)),
  CHECK(("end__state"=2 AND "end" IS NOT NULL) OR ("end__state" IN (0,1) AND "end" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='interval')
) STRICT;

CREATE TABLE "r_validity_v4" (
  __row_id INTEGER PRIMARY KEY,
  "calendar__state" INTEGER NOT NULL CHECK("calendar__state" IN (2)),
  "calendar" TEXT,
  "start__state" INTEGER NOT NULL CHECK("start__state" IN (2)),
  "start" INTEGER REFERENCES "r_temporal_bound"(__row_id),
  "end__state" INTEGER NOT NULL CHECK("end__state" IN (2)),
  "end" INTEGER REFERENCES "r_temporal_bound"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("calendar__state"=2 AND "calendar" IS NOT NULL) OR ("calendar__state" IN (0,1) AND "calendar" IS NULL)),
  CHECK(("start__state"=2 AND "start" IS NOT NULL) OR ("start__state" IN (0,1) AND "start" IS NULL)),
  CHECK(("end__state"=2 AND "end" IS NOT NULL) OR ("end__state" IN (0,1) AND "end" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='calendar_interval')
) STRICT;

CREATE TABLE "r_validity_v5" (
  __row_id INTEGER PRIMARY KEY,
  "from__state" INTEGER NOT NULL CHECK("from__state" IN (2)),
  "from" INTEGER REFERENCES "r_temporal_bound"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("from__state"=2 AND "from" IS NOT NULL) OR ("from__state" IN (0,1) AND "from" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='persistent_until_changed')
) STRICT;

CREATE TABLE "r_validity_v6" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='condition_dependent')
) STRICT;

CREATE TABLE "r_payload_v0_classification" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v0_world_associations" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v0_world_associations_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v0_world_associations"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_world_association"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_world_association" (
  __row_id INTEGER PRIMARY KEY,
  "world__state" INTEGER NOT NULL CHECK("world__state" IN (2)),
  "world" TEXT,
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "qualifiers__state" INTEGER NOT NULL CHECK("qualifiers__state" IN (2)),
  "qualifiers" INTEGER REFERENCES "r_world_association_qualifiers"(__row_id),
  CHECK(("world__state"=2 AND "world" IS NOT NULL) OR ("world__state" IN (0,1) AND "world" IS NULL)),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("qualifiers__state"=2 AND "qualifiers" IS NOT NULL) OR ("qualifiers__state" IN (0,1) AND "qualifiers" IS NULL))
) STRICT;

CREATE TABLE "r_world_association_qualifiers" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_world_association_qualifiers_items" (owner INTEGER NOT NULL REFERENCES "r_world_association_qualifiers"(__row_id), name TEXT NOT NULL, item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v0_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v0_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v0_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v0_metadata" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v0_metadata_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v0_metadata"(__row_id), name TEXT NOT NULL, item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v1" (
  __row_id INTEGER PRIMARY KEY,
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" INTEGER REFERENCES "r_appearance_target"(__row_id),
  "label__state" INTEGER NOT NULL CHECK("label__state" IN (2)),
  "label" TEXT,
  "physical_description__state" INTEGER NOT NULL CHECK("physical_description__state" IN (2)),
  "physical_description" TEXT,
  "atmosphere__state" INTEGER NOT NULL CHECK("atmosphere__state" IN (2)),
  "atmosphere" TEXT,
  "images__state" INTEGER NOT NULL CHECK("images__state" IN (2)),
  "images" INTEGER REFERENCES "r_payload_v1_images"(__row_id),
  "links__state" INTEGER NOT NULL CHECK("links__state" IN (2)),
  "links" INTEGER REFERENCES "r_payload_v1_links"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("label__state"=2 AND "label" IS NOT NULL) OR ("label__state" IN (0,1) AND "label" IS NULL)),
  CHECK(("physical_description__state"=2 AND "physical_description" IS NOT NULL) OR ("physical_description__state" IN (0,1) AND "physical_description" IS NULL)),
  CHECK(("atmosphere__state"=2 AND "atmosphere" IS NOT NULL) OR ("atmosphere__state" IN (0,1) AND "atmosphere" IS NULL)),
  CHECK(("images__state"=2 AND "images" IS NOT NULL) OR ("images__state" IN (0,1) AND "images" IS NULL)),
  CHECK(("links__state"=2 AND "links" IS NOT NULL) OR ("links__state" IN (0,1) AND "links" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='appearance')
) STRICT;

CREATE TABLE "r_appearance_target" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_appearance_target_v0"(__row_id),
  v1 INTEGER REFERENCES "r_appearance_target_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_appearance_target_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='universe')
) STRICT;

CREATE TABLE "r_appearance_target_v1" (
  __row_id INTEGER PRIMARY KEY,
  "entry__state" INTEGER NOT NULL CHECK("entry__state" IN (2)),
  "entry" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("entry__state"=2 AND "entry" IS NOT NULL) OR ("entry__state" IN (0,1) AND "entry" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='entry')
) STRICT;

CREATE TABLE "r_payload_v1_images" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v1_images_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v1_images"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_appearance_image"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_appearance_image" (
  __row_id INTEGER PRIMARY KEY,
  "asset__state" INTEGER NOT NULL CHECK("asset__state" IN (2)),
  "asset" INTEGER REFERENCES "r_record_ref"(__row_id),
  "caption__state" INTEGER NOT NULL CHECK("caption__state" IN (2)),
  "caption" TEXT,
  "purpose__state" INTEGER NOT NULL CHECK("purpose__state" IN (2)),
  "purpose" TEXT,
  CHECK(("asset__state"=2 AND "asset" IS NOT NULL) OR ("asset__state" IN (0,1) AND "asset" IS NULL)),
  CHECK(("caption__state"=2 AND "caption" IS NOT NULL) OR ("caption__state" IN (0,1) AND "caption" IS NULL)),
  CHECK(("purpose__state"=2 AND "purpose" IS NOT NULL) OR ("purpose__state" IN (0,1) AND "purpose" IS NULL)),
  CHECK("purpose" IN ('appearance','detail','inspiration'))
) STRICT;

CREATE TABLE "r_payload_v1_links" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v1_links_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v1_links"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_appearance_link"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_appearance_link" (
  __row_id INTEGER PRIMARY KEY,
  "entry__state" INTEGER NOT NULL CHECK("entry__state" IN (2)),
  "entry" INTEGER REFERENCES "r_record_ref"(__row_id),
  "relationship__state" INTEGER NOT NULL CHECK("relationship__state" IN (2)),
  "relationship" TEXT,
  "note__state" INTEGER NOT NULL CHECK("note__state" IN (2)),
  "note" TEXT,
  CHECK(("entry__state"=2 AND "entry" IS NOT NULL) OR ("entry__state" IN (0,1) AND "entry" IS NULL)),
  CHECK(("relationship__state"=2 AND "relationship" IS NOT NULL) OR ("relationship__state" IN (0,1) AND "relationship" IS NULL)),
  CHECK("relationship" IN ('matches','complements','contrasts','detail_of')),
  CHECK(("note__state"=2 AND "note" IS NOT NULL) OR ("note__state" IN (0,1) AND "note" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v2" (
  __row_id INTEGER PRIMARY KEY,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  "media_type__state" INTEGER NOT NULL CHECK("media_type__state" IN (2)),
  "media_type" TEXT,
  "byte_size__state" INTEGER NOT NULL CHECK("byte_size__state" IN (2)),
  "byte_size" TEXT,
  "width__state" INTEGER NOT NULL CHECK("width__state" IN (2)),
  "width" TEXT,
  "height__state" INTEGER NOT NULL CHECK("height__state" IN (2)),
  "height" TEXT,
  "original_name__state" INTEGER NOT NULL CHECK("original_name__state" IN (2)),
  "original_name" TEXT,
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL)),
  CHECK(("media_type__state"=2 AND "media_type" IS NOT NULL) OR ("media_type__state" IN (0,1) AND "media_type" IS NULL)),
  CHECK(("byte_size__state"=2 AND "byte_size" IS NOT NULL) OR ("byte_size__state" IN (0,1) AND "byte_size" IS NULL)),
  CHECK(("width__state"=2 AND "width" IS NOT NULL) OR ("width__state" IN (0,1) AND "width" IS NULL)),
  CHECK(("height__state"=2 AND "height" IS NOT NULL) OR ("height__state" IN (0,1) AND "height" IS NULL)),
  CHECK(("original_name__state"=2 AND "original_name" IS NOT NULL) OR ("original_name__state" IN (0,1) AND "original_name" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='image_asset')
) STRICT;

CREATE TABLE "r_payload_v3" (
  __row_id INTEGER PRIMARY KEY,
  "selector__state" INTEGER NOT NULL CHECK("selector__state" IN (2)),
  "selector" TEXT,
  "aliases__state" INTEGER NOT NULL CHECK("aliases__state" IN (0,2)),
  "aliases" INTEGER REFERENCES "r_payload_v3_aliases"(__row_id),
  "settingType__state" INTEGER NOT NULL CHECK("settingType__state" IN (0,1,2)),
  "settingType" INTEGER REFERENCES "r_payload_v3_setting_type"(__row_id),
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (0,2)),
  "labels" INTEGER REFERENCES "r_payload_v3_labels"(__row_id),
  "metadata__state" INTEGER NOT NULL CHECK("metadata__state" IN (0,2)),
  "metadata" INTEGER REFERENCES "r_payload_v3_metadata"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("selector__state"=2 AND "selector" IS NOT NULL) OR ("selector__state" IN (0,1) AND "selector" IS NULL)),
  CHECK(("aliases__state"=2 AND "aliases" IS NOT NULL) OR ("aliases__state" IN (0,1) AND "aliases" IS NULL)),
  CHECK(("settingType__state"=2 AND "settingType" IS NOT NULL) OR ("settingType__state" IN (0,1) AND "settingType" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("metadata__state"=2 AND "metadata" IS NOT NULL) OR ("metadata__state" IN (0,1) AND "metadata" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='world')
) STRICT;

CREATE TABLE "r_payload_v3_aliases" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v3_aliases_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v3_aliases"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v3_setting_type" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v3_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v3_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v3_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v3_metadata" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v3_metadata_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v3_metadata"(__row_id), name TEXT NOT NULL, item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v4" (
  __row_id INTEGER PRIMARY KEY,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v4_labels"(__row_id),
  "metadata__state" INTEGER NOT NULL CHECK("metadata__state" IN (2)),
  "metadata" INTEGER REFERENCES "r_payload_v4_metadata"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("metadata__state"=2 AND "metadata" IS NOT NULL) OR ("metadata__state" IN (0,1) AND "metadata" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='realm')
) STRICT;

CREATE TABLE "r_payload_v4_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v4_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v4_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v4_metadata" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v4_metadata_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v4_metadata"(__row_id), name TEXT NOT NULL, item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v5" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" INTEGER REFERENCES "r_work_kind"(__row_id),
  "title__state" INTEGER NOT NULL CHECK("title__state" IN (2)),
  "title" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v5_labels"(__row_id),
  "sourceRefs__state" INTEGER NOT NULL CHECK("sourceRefs__state" IN (2)),
  "sourceRefs" INTEGER REFERENCES "r_payload_v5_source_refs"(__row_id),
  "versions__state" INTEGER NOT NULL CHECK("versions__state" IN (2)),
  "versions" INTEGER REFERENCES "r_payload_v5_versions"(__row_id),
  "worldAssociations__state" INTEGER NOT NULL CHECK("worldAssociations__state" IN (2)),
  "worldAssociations" INTEGER REFERENCES "r_payload_v5_world_associations"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK(("title__state"=2 AND "title" IS NOT NULL) OR ("title__state" IN (0,1) AND "title" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("sourceRefs__state"=2 AND "sourceRefs" IS NOT NULL) OR ("sourceRefs__state" IN (0,1) AND "sourceRefs" IS NULL)),
  CHECK(("versions__state"=2 AND "versions" IS NOT NULL) OR ("versions__state" IN (0,1) AND "versions" IS NULL)),
  CHECK(("worldAssociations__state"=2 AND "worldAssociations" IS NOT NULL) OR ("worldAssociations__state" IN (0,1) AND "worldAssociations" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='work')
) STRICT;

CREATE TABLE "r_work_kind" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_payload_v5_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v5_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v5_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v5_source_refs" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v5_source_refs_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v5_source_refs"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v5_versions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v5_versions_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v5_versions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v5_world_associations" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v5_world_associations_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v5_world_associations"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_world_association"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v6" (
  __row_id INTEGER PRIMARY KEY,
  "work__state" INTEGER NOT NULL CHECK("work__state" IN (2)),
  "work" INTEGER REFERENCES "r_record_ref"(__row_id),
  "versionLabel__state" INTEGER NOT NULL CHECK("versionLabel__state" IN (2)),
  "versionLabel" TEXT,
  "binding__state" INTEGER NOT NULL CHECK("binding__state" IN (2)),
  "binding" INTEGER REFERENCES "r_work_binding"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("work__state"=2 AND "work" IS NOT NULL) OR ("work__state" IN (0,1) AND "work" IS NULL)),
  CHECK(("versionLabel__state"=2 AND "versionLabel" IS NOT NULL) OR ("versionLabel__state" IN (0,1) AND "versionLabel" IS NULL)),
  CHECK(("binding__state"=2 AND "binding" IS NOT NULL) OR ("binding__state" IN (0,1) AND "binding" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='work_version')
) STRICT;

CREATE TABLE "r_work_binding" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 2),
  v0 INTEGER REFERENCES "r_work_binding_v0"(__row_id),
  v1 INTEGER REFERENCES "r_work_binding_v1"(__row_id),
  v2 INTEGER REFERENCES "r_work_binding_v2"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL)
) STRICT;

CREATE TABLE "r_work_binding_v0" (
  __row_id INTEGER PRIMARY KEY,
  "continuity__state" INTEGER NOT NULL CHECK("continuity__state" IN (2)),
  "continuity" TEXT,
  "revision__state" INTEGER NOT NULL CHECK("revision__state" IN (2)),
  "revision" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("continuity__state"=2 AND "continuity" IS NOT NULL) OR ("continuity__state" IN (0,1) AND "continuity" IS NULL)),
  CHECK(("revision__state"=2 AND "revision" IS NOT NULL) OR ("revision__state" IN (0,1) AND "revision" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='bound')
) STRICT;

CREATE TABLE "r_work_binding_v1" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unbound')
) STRICT;

CREATE TABLE "r_work_binding_v2" (
  __row_id INTEGER PRIMARY KEY,
  "segments__state" INTEGER NOT NULL CHECK("segments__state" IN (2)),
  "segments" INTEGER REFERENCES "r_work_binding_v2_segments"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("segments__state"=2 AND "segments" IS NOT NULL) OR ("segments__state" IN (0,1) AND "segments" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='segments')
) STRICT;

CREATE TABLE "r_work_binding_v2_segments" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_work_binding_v2_segments_items" (owner INTEGER NOT NULL REFERENCES "r_work_binding_v2_segments"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_work_segment"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_work_segment" (
  __row_id INTEGER PRIMARY KEY,
  "segment__state" INTEGER NOT NULL CHECK("segment__state" IN (2)),
  "segment" TEXT,
  "continuity__state" INTEGER NOT NULL CHECK("continuity__state" IN (2)),
  "continuity" TEXT,
  "revision__state" INTEGER NOT NULL CHECK("revision__state" IN (2)),
  "revision" TEXT,
  CHECK(("segment__state"=2 AND "segment" IS NOT NULL) OR ("segment__state" IN (0,1) AND "segment" IS NULL)),
  CHECK(("continuity__state"=2 AND "continuity" IS NOT NULL) OR ("continuity__state" IN (0,1) AND "continuity" IS NULL)),
  CHECK(("revision__state"=2 AND "revision" IS NOT NULL) OR ("revision__state" IN (0,1) AND "revision" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v7" (
  __row_id INTEGER PRIMARY KEY,
  "workVersion__state" INTEGER NOT NULL CHECK("workVersion__state" IN (2)),
  "workVersion" INTEGER REFERENCES "r_version_ref"(__row_id),
  "sceneId__state" INTEGER NOT NULL CHECK("sceneId__state" IN (2)),
  "sceneId" TEXT,
  "disclosedRecords__state" INTEGER NOT NULL CHECK("disclosedRecords__state" IN (0,2)),
  "disclosedRecords" INTEGER REFERENCES "r_payload_v7_disclosed_records"(__row_id),
  "viewpoint__state" INTEGER NOT NULL CHECK("viewpoint__state" IN (0,1,2)),
  "viewpoint" INTEGER REFERENCES "r_payload_v7_viewpoint"(__row_id),
  "narrativePosition__state" INTEGER NOT NULL CHECK("narrativePosition__state" IN (0,1,2)),
  "narrativePosition" INTEGER REFERENCES "r_payload_v7_narrative_position"(__row_id),
  "depictedEvents__state" INTEGER NOT NULL CHECK("depictedEvents__state" IN (2)),
  "depictedEvents" INTEGER REFERENCES "r_payload_v7_depicted_events"(__row_id),
  "narrationFrame__state" INTEGER NOT NULL CHECK("narrationFrame__state" IN (0,1,2)),
  "narrationFrame" INTEGER REFERENCES "r_payload_v7_narration_frame"(__row_id),
  "worldAssociations__state" INTEGER NOT NULL CHECK("worldAssociations__state" IN (2)),
  "worldAssociations" INTEGER REFERENCES "r_payload_v7_world_associations"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("workVersion__state"=2 AND "workVersion" IS NOT NULL) OR ("workVersion__state" IN (0,1) AND "workVersion" IS NULL)),
  CHECK(("sceneId__state"=2 AND "sceneId" IS NOT NULL) OR ("sceneId__state" IN (0,1) AND "sceneId" IS NULL)),
  CHECK(("disclosedRecords__state"=2 AND "disclosedRecords" IS NOT NULL) OR ("disclosedRecords__state" IN (0,1) AND "disclosedRecords" IS NULL)),
  CHECK(("viewpoint__state"=2 AND "viewpoint" IS NOT NULL) OR ("viewpoint__state" IN (0,1) AND "viewpoint" IS NULL)),
  CHECK(("narrativePosition__state"=2 AND "narrativePosition" IS NOT NULL) OR ("narrativePosition__state" IN (0,1) AND "narrativePosition" IS NULL)),
  CHECK(("depictedEvents__state"=2 AND "depictedEvents" IS NOT NULL) OR ("depictedEvents__state" IN (0,1) AND "depictedEvents" IS NULL)),
  CHECK(("narrationFrame__state"=2 AND "narrationFrame" IS NOT NULL) OR ("narrationFrame__state" IN (0,1) AND "narrationFrame" IS NULL)),
  CHECK(("worldAssociations__state"=2 AND "worldAssociations" IS NOT NULL) OR ("worldAssociations__state" IN (0,1) AND "worldAssociations" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='scene_ref')
) STRICT;

CREATE TABLE "r_version_ref" (
  __row_id INTEGER PRIMARY KEY,
  "universe__state" INTEGER NOT NULL CHECK("universe__state" IN (0,1,2)),
  "universe" INTEGER REFERENCES "r_version_ref_universe"(__row_id),
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  CHECK(("universe__state"=2 AND "universe" IS NOT NULL) OR ("universe__state" IN (0,1) AND "universe" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL))
) STRICT;

CREATE TABLE "r_version_ref_universe" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v7_disclosed_records" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v7_disclosed_records_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v7_disclosed_records"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v7_viewpoint" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v7_narrative_position" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v7_depicted_events" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v7_depicted_events_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v7_depicted_events"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v7_narration_frame" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v7_world_associations" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v7_world_associations_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v7_world_associations"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_world_association"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v8" (
  __row_id INTEGER PRIMARY KEY,
  "workVersion__state" INTEGER NOT NULL CHECK("workVersion__state" IN (2)),
  "workVersion" INTEGER REFERENCES "r_version_ref"(__row_id),
  "passageId__state" INTEGER NOT NULL CHECK("passageId__state" IN (2)),
  "passageId" TEXT,
  "anchor__state" INTEGER NOT NULL CHECK("anchor__state" IN (0,1,2)),
  "anchor" INTEGER REFERENCES "r_payload_v8_anchor"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("workVersion__state"=2 AND "workVersion" IS NOT NULL) OR ("workVersion__state" IN (0,1) AND "workVersion" IS NULL)),
  CHECK(("passageId__state"=2 AND "passageId" IS NOT NULL) OR ("passageId__state" IN (0,1) AND "passageId" IS NULL)),
  CHECK(("anchor__state"=2 AND "anchor" IS NOT NULL) OR ("anchor__state" IN (0,1) AND "anchor" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='passage_ref')
) STRICT;

CREATE TABLE "r_payload_v8_anchor" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v9" (
  __row_id INTEGER PRIMARY KEY,
  "title__state" INTEGER NOT NULL CHECK("title__state" IN (2)),
  "title" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v9_labels"(__row_id),
  "memberships__state" INTEGER NOT NULL CHECK("memberships__state" IN (2)),
  "memberships" INTEGER REFERENCES "r_payload_v9_memberships"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("title__state"=2 AND "title" IS NOT NULL) OR ("title__state" IN (0,1) AND "title" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("memberships__state"=2 AND "memberships" IS NOT NULL) OR ("memberships__state" IN (0,1) AND "memberships" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='saga')
) STRICT;

CREATE TABLE "r_payload_v9_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v9_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v9_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v9_memberships" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v9_memberships_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v9_memberships"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_saga_membership"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_saga_membership" (
  __row_id INTEGER PRIMARY KEY,
  "work__state" INTEGER NOT NULL CHECK("work__state" IN (2)),
  "work" INTEGER REFERENCES "r_record_ref"(__row_id),
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  "order__state" INTEGER NOT NULL CHECK("order__state" IN (0,1,2)),
  "order" INTEGER REFERENCES "r_saga_membership_order"(__row_id),
  CHECK(("work__state"=2 AND "work" IS NOT NULL) OR ("work__state" IN (0,1) AND "work" IS NULL)),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("order__state"=2 AND "order" IS NOT NULL) OR ("order__state" IN (0,1) AND "order" IS NULL))
) STRICT;

CREATE TABLE "r_saga_membership_order" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v10" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v10_labels"(__row_id),
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "parent__state" INTEGER NOT NULL CHECK("parent__state" IN (1,2)),
  "parent" INTEGER REFERENCES "r_payload_v10_parent"(__row_id),
  "parentResolution__state" INTEGER NOT NULL CHECK("parentResolution__state" IN (2)),
  "parentResolution" TEXT,
  "applicability__state" INTEGER NOT NULL CHECK("applicability__state" IN (2)),
  "applicability" INTEGER REFERENCES "r_applicability"(__row_id),
  "classificationExecutable__state" INTEGER NOT NULL CHECK("classificationExecutable__state" IN (2)),
  "classificationExecutable" INTEGER,
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("parent__state"=2 AND "parent" IS NOT NULL) OR ("parent__state" IN (0,1) AND "parent" IS NULL)),
  CHECK(("parentResolution__state"=2 AND "parentResolution" IS NOT NULL) OR ("parentResolution__state" IN (0,1) AND "parentResolution" IS NULL)),
  CHECK("parentResolution" IN ('root','resolved','ambiguous')),
  CHECK(("applicability__state"=2 AND "applicability" IS NOT NULL) OR ("applicability__state" IN (0,1) AND "applicability" IS NULL)),
  CHECK(("classificationExecutable__state"=2 AND "classificationExecutable" IS NOT NULL) OR ("classificationExecutable__state" IN (0,1) AND "classificationExecutable" IS NULL)),
  CHECK("classificationExecutable" IN (0,1)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='entity_type')
) STRICT;

CREATE TABLE "r_payload_v10_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v10_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v10_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v10_parent" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_applicability" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 3),
  v0 INTEGER REFERENCES "r_applicability_v0"(__row_id),
  v1 INTEGER REFERENCES "r_applicability_v1"(__row_id),
  v2 INTEGER REFERENCES "r_applicability_v2"(__row_id),
  v3 INTEGER REFERENCES "r_applicability_v3"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL)
) STRICT;

CREATE TABLE "r_applicability_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='universe_wide')
) STRICT;

CREATE TABLE "r_applicability_v1" (
  __row_id INTEGER PRIMARY KEY,
  "world_ids__state" INTEGER NOT NULL CHECK("world_ids__state" IN (2)),
  "world_ids" INTEGER REFERENCES "r_applicability_v1_world_ids"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("world_ids__state"=2 AND "world_ids" IS NOT NULL) OR ("world_ids__state" IN (0,1) AND "world_ids" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='worlds')
) STRICT;

CREATE TABLE "r_applicability_v1_world_ids" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_applicability_v1_world_ids_items" (owner INTEGER NOT NULL REFERENCES "r_applicability_v1_world_ids"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_applicability_v2" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='conditional')
) STRICT;

CREATE TABLE "r_applicability_v3" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unspecified')
) STRICT;

CREATE TABLE "r_payload_v11" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v11_labels"(__row_id),
  "subjectTypes__state" INTEGER NOT NULL CHECK("subjectTypes__state" IN (0,2)),
  "subjectTypes" INTEGER REFERENCES "r_payload_v11_subject_types"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value_shape"(__row_id),
  "multiplicity__state" INTEGER NOT NULL CHECK("multiplicity__state" IN (2)),
  "multiplicity" TEXT,
  "unitDimension__state" INTEGER NOT NULL CHECK("unitDimension__state" IN (0,1,2)),
  "unitDimension" INTEGER REFERENCES "r_payload_v11_unit_dimension"(__row_id),
  "persistence__state" INTEGER NOT NULL CHECK("persistence__state" IN (2)),
  "persistence" INTEGER REFERENCES "r_persistence_semantics"(__row_id),
  "exclusive__state" INTEGER NOT NULL CHECK("exclusive__state" IN (2)),
  "exclusive" INTEGER,
  "inverse__state" INTEGER NOT NULL CHECK("inverse__state" IN (0,1,2)),
  "inverse" INTEGER REFERENCES "r_payload_v11_inverse"(__row_id),
  "symmetric__state" INTEGER NOT NULL CHECK("symmetric__state" IN (2)),
  "symmetric" INTEGER,
  "transitive__state" INTEGER NOT NULL CHECK("transitive__state" IN (2)),
  "transitive" INTEGER,
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("subjectTypes__state"=2 AND "subjectTypes" IS NOT NULL) OR ("subjectTypes__state" IN (0,1) AND "subjectTypes" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("multiplicity__state"=2 AND "multiplicity" IS NOT NULL) OR ("multiplicity__state" IN (0,1) AND "multiplicity" IS NULL)),
  CHECK("multiplicity" IN ('single','multiple')),
  CHECK(("unitDimension__state"=2 AND "unitDimension" IS NOT NULL) OR ("unitDimension__state" IN (0,1) AND "unitDimension" IS NULL)),
  CHECK(("persistence__state"=2 AND "persistence" IS NOT NULL) OR ("persistence__state" IN (0,1) AND "persistence" IS NULL)),
  CHECK(("exclusive__state"=2 AND "exclusive" IS NOT NULL) OR ("exclusive__state" IN (0,1) AND "exclusive" IS NULL)),
  CHECK("exclusive" IN (0,1)),
  CHECK(("inverse__state"=2 AND "inverse" IS NOT NULL) OR ("inverse__state" IN (0,1) AND "inverse" IS NULL)),
  CHECK(("symmetric__state"=2 AND "symmetric" IS NOT NULL) OR ("symmetric__state" IN (0,1) AND "symmetric" IS NULL)),
  CHECK("symmetric" IN (0,1)),
  CHECK(("transitive__state"=2 AND "transitive" IS NOT NULL) OR ("transitive__state" IN (0,1) AND "transitive" IS NULL)),
  CHECK("transitive" IN (0,1)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='property')
) STRICT;

CREATE TABLE "r_payload_v11_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v11_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v11_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v11_subject_types" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v11_subject_types_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v11_subject_types"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_value_shape" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 13),
  v0 INTEGER REFERENCES "r_value_shape_v0"(__row_id),
  v1 INTEGER REFERENCES "r_value_shape_v1"(__row_id),
  v2 INTEGER REFERENCES "r_value_shape_v2"(__row_id),
  v3 INTEGER REFERENCES "r_value_shape_v3"(__row_id),
  v4 INTEGER REFERENCES "r_value_shape_v4"(__row_id),
  v5 INTEGER REFERENCES "r_value_shape_v5"(__row_id),
  v6 INTEGER REFERENCES "r_value_shape_v6"(__row_id),
  v7 INTEGER REFERENCES "r_value_shape_v7"(__row_id),
  v8 INTEGER REFERENCES "r_value_shape_v8"(__row_id),
  v9 INTEGER REFERENCES "r_value_shape_v9"(__row_id),
  v10 INTEGER REFERENCES "r_value_shape_v10"(__row_id),
  v11 INTEGER REFERENCES "r_value_shape_v11"(__row_id),
  v12 INTEGER REFERENCES "r_value_shape_v12"(__row_id),
  v13 INTEGER REFERENCES "r_value_shape_v13"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL),
  CHECK(variant=6 OR v6 IS NULL),
  CHECK(variant!=6 OR v6 IS NOT NULL),
  CHECK(variant=7 OR v7 IS NULL),
  CHECK(variant!=7 OR v7 IS NOT NULL),
  CHECK(variant=8 OR v8 IS NULL),
  CHECK(variant!=8 OR v8 IS NOT NULL),
  CHECK(variant=9 OR v9 IS NULL),
  CHECK(variant!=9 OR v9 IS NOT NULL),
  CHECK(variant=10 OR v10 IS NULL),
  CHECK(variant!=10 OR v10 IS NOT NULL),
  CHECK(variant=11 OR v11 IS NULL),
  CHECK(variant!=11 OR v11 IS NOT NULL),
  CHECK(variant=12 OR v12 IS NULL),
  CHECK(variant!=12 OR v12 IS NOT NULL),
  CHECK(variant=13 OR v13 IS NULL),
  CHECK(variant!=13 OR v13 IS NOT NULL)
) STRICT;

CREATE TABLE "r_value_shape_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='text')
) STRICT;

CREATE TABLE "r_value_shape_v1" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='boolean')
) STRICT;

CREATE TABLE "r_value_shape_v2" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='integer')
) STRICT;

CREATE TABLE "r_value_shape_v3" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='decimal')
) STRICT;

CREATE TABLE "r_value_shape_v4" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='rational')
) STRICT;

CREATE TABLE "r_value_shape_v5" (
  __row_id INTEGER PRIMARY KEY,
  "unit__state" INTEGER NOT NULL CHECK("unit__state" IN (2)),
  "unit" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("unit__state"=2 AND "unit" IS NOT NULL) OR ("unit__state" IN (0,1) AND "unit" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='quantity')
) STRICT;

CREATE TABLE "r_value_shape_v6" (
  __row_id INTEGER PRIMARY KEY,
  "unit__state" INTEGER NOT NULL CHECK("unit__state" IN (0,1,2)),
  "unit" INTEGER REFERENCES "r_value_shape_v6_unit"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("unit__state"=2 AND "unit" IS NOT NULL) OR ("unit__state" IN (0,1) AND "unit" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='range')
) STRICT;

CREATE TABLE "r_value_shape_v6_unit" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_value_shape_v7" (
  __row_id INTEGER PRIMARY KEY,
  "subject_types__state" INTEGER NOT NULL CHECK("subject_types__state" IN (2)),
  "subject_types" INTEGER REFERENCES "r_value_shape_v7_subject_types"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("subject_types__state"=2 AND "subject_types" IS NOT NULL) OR ("subject_types__state" IN (0,1) AND "subject_types" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='entity_ref')
) STRICT;

CREATE TABLE "r_value_shape_v7_subject_types" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_value_shape_v7_subject_types_items" (owner INTEGER NOT NULL REFERENCES "r_value_shape_v7_subject_types"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_value_shape_v8" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='temporal')
) STRICT;

CREATE TABLE "r_value_shape_v9" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='spatial')
) STRICT;

CREATE TABLE "r_value_shape_v10" (
  __row_id INTEGER PRIMARY KEY,
  "definition__state" INTEGER NOT NULL CHECK("definition__state" IN (2)),
  "definition" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("definition__state"=2 AND "definition" IS NOT NULL) OR ("definition__state" IN (0,1) AND "definition" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='enum')
) STRICT;

CREATE TABLE "r_value_shape_v11" (
  __row_id INTEGER PRIMARY KEY,
  "item__state" INTEGER NOT NULL CHECK("item__state" IN (2)),
  "item" INTEGER REFERENCES "r_value_shape"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("item__state"=2 AND "item" IS NOT NULL) OR ("item__state" IN (0,1) AND "item" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='sequence')
) STRICT;

CREATE TABLE "r_value_shape_v12" (
  __row_id INTEGER PRIMARY KEY,
  "definition__state" INTEGER NOT NULL CHECK("definition__state" IN (2)),
  "definition" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("definition__state"=2 AND "definition" IS NOT NULL) OR ("definition__state" IN (0,1) AND "definition" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='structured')
) STRICT;

CREATE TABLE "r_value_shape_v13" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unspecified')
) STRICT;

CREATE TABLE "r_payload_v11_unit_dimension" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_persistence_semantics" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 4),
  v0 TEXT,
  v1 TEXT,
  v2 TEXT,
  v3 TEXT,
  v4 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL)
) STRICT;

CREATE TABLE "r_payload_v11_inverse" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v12" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v12_labels"(__row_id),
  "roles__state" INTEGER NOT NULL CHECK("roles__state" IN (2)),
  "roles" INTEGER REFERENCES "r_payload_v12_roles"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("roles__state"=2 AND "roles" IS NOT NULL) OR ("roles__state" IN (0,1) AND "roles" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='relation')
) STRICT;

CREATE TABLE "r_payload_v12_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v12_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v12_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v12_roles" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v12_roles_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v12_roles"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_role_def"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_role_def" (
  __row_id INTEGER PRIMARY KEY,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "participantTypes__state" INTEGER NOT NULL CHECK("participantTypes__state" IN (0,2)),
  "participantTypes" INTEGER REFERENCES "r_role_def_participant_types"(__row_id),
  "multiplicity__state" INTEGER NOT NULL CHECK("multiplicity__state" IN (2)),
  "multiplicity" TEXT,
  "ordered__state" INTEGER NOT NULL CHECK("ordered__state" IN (2)),
  "ordered" INTEGER,
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("participantTypes__state"=2 AND "participantTypes" IS NOT NULL) OR ("participantTypes__state" IN (0,1) AND "participantTypes" IS NULL)),
  CHECK(("multiplicity__state"=2 AND "multiplicity" IS NOT NULL) OR ("multiplicity__state" IN (0,1) AND "multiplicity" IS NULL)),
  CHECK("multiplicity" IN ('single','multiple')),
  CHECK(("ordered__state"=2 AND "ordered" IS NOT NULL) OR ("ordered__state" IN (0,1) AND "ordered" IS NULL)),
  CHECK("ordered" IN (0,1))
) STRICT;

CREATE TABLE "r_role_def_participant_types" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_role_def_participant_types_items" (owner INTEGER NOT NULL REFERENCES "r_role_def_participant_types"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v13" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "dimension__state" INTEGER NOT NULL CHECK("dimension__state" IN (2)),
  "dimension" TEXT,
  "symbol__state" INTEGER NOT NULL CHECK("symbol__state" IN (2)),
  "symbol" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v13_labels"(__row_id),
  "scaleToBase__state" INTEGER NOT NULL CHECK("scaleToBase__state" IN (0,1,2)),
  "scaleToBase" INTEGER REFERENCES "r_payload_v13_scale_to_base"(__row_id),
  "base__state" INTEGER NOT NULL CHECK("base__state" IN (0,1,2)),
  "base" INTEGER REFERENCES "r_payload_v13_base"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("dimension__state"=2 AND "dimension" IS NOT NULL) OR ("dimension__state" IN (0,1) AND "dimension" IS NULL)),
  CHECK(("symbol__state"=2 AND "symbol" IS NOT NULL) OR ("symbol__state" IN (0,1) AND "symbol" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("scaleToBase__state"=2 AND "scaleToBase" IS NOT NULL) OR ("scaleToBase__state" IN (0,1) AND "scaleToBase" IS NULL)),
  CHECK(("base__state"=2 AND "base" IS NOT NULL) OR ("base__state" IN (0,1) AND "base" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='unit')
) STRICT;

CREATE TABLE "r_payload_v13_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v13_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v13_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v13_scale_to_base" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_value"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v13_base" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v14" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v14_labels"(__row_id),
  "epoch__state" INTEGER NOT NULL CHECK("epoch__state" IN (0,1,2)),
  "epoch" INTEGER REFERENCES "r_payload_v14_epoch"(__row_id),
  "unitStructure__state" INTEGER NOT NULL CHECK("unitStructure__state" IN (2)),
  "unitStructure" INTEGER REFERENCES "r_payload_v14_unit_structure"(__row_id),
  "conversions__state" INTEGER NOT NULL CHECK("conversions__state" IN (0,2)),
  "conversions" INTEGER REFERENCES "r_payload_v14_conversions"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("epoch__state"=2 AND "epoch" IS NOT NULL) OR ("epoch__state" IN (0,1) AND "epoch" IS NULL)),
  CHECK(("unitStructure__state"=2 AND "unitStructure" IS NOT NULL) OR ("unitStructure__state" IN (0,1) AND "unitStructure" IS NULL)),
  CHECK(("conversions__state"=2 AND "conversions" IS NOT NULL) OR ("conversions__state" IN (0,1) AND "conversions" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='calendar')
) STRICT;

CREATE TABLE "r_payload_v14_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v14_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v14_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v14_epoch" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v14_unit_structure" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v14_unit_structure_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v14_unit_structure"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v14_conversions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v14_conversions_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v14_conversions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_calendar_conversion"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_calendar_conversion" (
  __row_id INTEGER PRIMARY KEY,
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" TEXT,
  "expression__state" INTEGER NOT NULL CHECK("expression__state" IN (0,1,2)),
  "expression" INTEGER REFERENCES "r_calendar_conversion_expression"(__row_id),
  "valid__state" INTEGER NOT NULL CHECK("valid__state" IN (2)),
  "valid" INTEGER,
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("expression__state"=2 AND "expression" IS NOT NULL) OR ("expression__state" IN (0,1) AND "expression" IS NULL)),
  CHECK(("valid__state"=2 AND "valid" IS NOT NULL) OR ("valid__state" IN (0,1) AND "valid" IS NULL)),
  CHECK("valid" IN (0,1))
) STRICT;

CREATE TABLE "r_calendar_conversion_expression" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v15" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v15_labels"(__row_id),
  "fields__state" INTEGER NOT NULL CHECK("fields__state" IN (2)),
  "fields" INTEGER REFERENCES "r_payload_v15_fields"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("fields__state"=2 AND "fields" IS NOT NULL) OR ("fields__state" IN (0,1) AND "fields" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='value_definition')
) STRICT;

CREATE TABLE "r_payload_v15_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v15_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v15_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v15_fields" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v15_fields_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v15_fields"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_value_def_field"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_value_def_field" (
  __row_id INTEGER PRIMARY KEY,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "shape__state" INTEGER NOT NULL CHECK("shape__state" IN (2)),
  "shape" INTEGER REFERENCES "r_value_shape"(__row_id),
  "required__state" INTEGER NOT NULL CHECK("required__state" IN (2)),
  "required" INTEGER,
  "allowsUnknown__state" INTEGER NOT NULL CHECK("allowsUnknown__state" IN (2)),
  "allowsUnknown" INTEGER,
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("shape__state"=2 AND "shape" IS NOT NULL) OR ("shape__state" IN (0,1) AND "shape" IS NULL)),
  CHECK(("required__state"=2 AND "required" IS NOT NULL) OR ("required__state" IN (0,1) AND "required" IS NULL)),
  CHECK("required" IN (0,1)),
  CHECK(("allowsUnknown__state"=2 AND "allowsUnknown" IS NOT NULL) OR ("allowsUnknown__state" IN (0,1) AND "allowsUnknown" IS NULL)),
  CHECK("allowsUnknown" IN (0,1))
) STRICT;

CREATE TABLE "r_payload_v16" (
  __row_id INTEGER PRIMARY KEY,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  "dependencies__state" INTEGER NOT NULL CHECK("dependencies__state" IN (2)),
  "dependencies" INTEGER REFERENCES "r_payload_v16_dependencies"(__row_id),
  "capabilities__state" INTEGER NOT NULL CHECK("capabilities__state" IN (2)),
  "capabilities" INTEGER REFERENCES "r_payload_v16_capabilities"(__row_id),
  "records__state" INTEGER NOT NULL CHECK("records__state" IN (2)),
  "records" INTEGER REFERENCES "r_payload_v16_records"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL)),
  CHECK(("dependencies__state"=2 AND "dependencies" IS NOT NULL) OR ("dependencies__state" IN (0,1) AND "dependencies" IS NULL)),
  CHECK(("capabilities__state"=2 AND "capabilities" IS NOT NULL) OR ("capabilities__state" IN (0,1) AND "capabilities" IS NULL)),
  CHECK(("records__state"=2 AND "records" IS NOT NULL) OR ("records__state" IN (0,1) AND "records" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='domain_pack')
) STRICT;

CREATE TABLE "r_payload_v16_dependencies" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v16_dependencies_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v16_dependencies"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v16_capabilities" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v16_capabilities_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v16_capabilities"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v16_records" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v16_records_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v16_records"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v17" (
  __row_id INTEGER PRIMARY KEY,
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" INTEGER REFERENCES "r_record_ref"(__row_id),
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_record_ref"(__row_id),
  "roles__state" INTEGER NOT NULL CHECK("roles__state" IN (0,2)),
  "roles" INTEGER REFERENCES "r_payload_v17_roles"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (0,1,2)),
  "value" INTEGER REFERENCES "r_payload_v17_value"(__row_id),
  "quantification__state" INTEGER NOT NULL CHECK("quantification__state" IN (2)),
  "quantification" INTEGER REFERENCES "r_quantification"(__row_id),
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (2)),
  "context" INTEGER REFERENCES "r_record_ref"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("roles__state"=2 AND "roles" IS NOT NULL) OR ("roles__state" IN (0,1) AND "roles" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("quantification__state"=2 AND "quantification" IS NOT NULL) OR ("quantification__state" IN (0,1) AND "quantification" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='proposition')
) STRICT;

CREATE TABLE "r_payload_v17_roles" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v17_roles_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v17_roles"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_proposition_role"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_proposition_role" (
  __row_id INTEGER PRIMARY KEY,
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  "participant__state" INTEGER NOT NULL CHECK("participant__state" IN (2)),
  "participant" INTEGER REFERENCES "r_record_ref"(__row_id),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("participant__state"=2 AND "participant" IS NOT NULL) OR ("participant__state" IN (0,1) AND "participant" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v17_value" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_value"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_quantification" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 2),
  v0 TEXT,
  v1 TEXT,
  v2 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL)
) STRICT;

CREATE TABLE "r_payload_v18" (
  __row_id INTEGER PRIMARY KEY,
  "attributeMode__state" INTEGER NOT NULL CHECK("attributeMode__state" IN (2)),
  "attributeMode" TEXT,
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" INTEGER REFERENCES "r_record_ref"(__row_id),
  "polarity__state" INTEGER NOT NULL CHECK("polarity__state" IN (2)),
  "polarity" TEXT,
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "persistence__state" INTEGER NOT NULL CHECK("persistence__state" IN (2)),
  "persistence" INTEGER REFERENCES "r_persistence_semantics"(__row_id),
  "precision__state" INTEGER NOT NULL CHECK("precision__state" IN (2)),
  "precision" TEXT,
  "alternatives__state" INTEGER NOT NULL CHECK("alternatives__state" IN (0,2)),
  "alternatives" INTEGER REFERENCES "r_payload_v18_alternatives"(__row_id),
  "basis__state" INTEGER NOT NULL CHECK("basis__state" IN (2)),
  "basis" INTEGER REFERENCES "r_evidence_basis"(__row_id),
  "establishedBy__state" INTEGER NOT NULL CHECK("establishedBy__state" IN (0,1,2)),
  "establishedBy" INTEGER REFERENCES "r_payload_v18_established_by"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("attributeMode__state"=2 AND "attributeMode" IS NOT NULL) OR ("attributeMode__state" IN (0,1) AND "attributeMode" IS NULL)),
  CHECK("attributeMode" IN ('instance','shared','initial_value')),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("polarity__state"=2 AND "polarity" IS NOT NULL) OR ("polarity__state" IN (0,1) AND "polarity" IS NULL)),
  CHECK("polarity" IN ('support','refutation')),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("persistence__state"=2 AND "persistence" IS NOT NULL) OR ("persistence__state" IN (0,1) AND "persistence" IS NULL)),
  CHECK(("precision__state"=2 AND "precision" IS NOT NULL) OR ("precision__state" IN (0,1) AND "precision" IS NULL)),
  CHECK("precision" IN ('exact','approximate','range','one_of','unresolved')),
  CHECK(("alternatives__state"=2 AND "alternatives" IS NOT NULL) OR ("alternatives__state" IN (0,1) AND "alternatives" IS NULL)),
  CHECK(("basis__state"=2 AND "basis" IS NOT NULL) OR ("basis__state" IN (0,1) AND "basis" IS NULL)),
  CHECK(("establishedBy__state"=2 AND "establishedBy" IS NOT NULL) OR ("establishedBy__state" IN (0,1) AND "establishedBy" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='assertion')
) STRICT;

CREATE TABLE "r_scope" (
  __row_id INTEGER PRIMARY KEY,
  "applicability__state" INTEGER NOT NULL CHECK("applicability__state" IN (2)),
  "applicability" INTEGER REFERENCES "r_applicability"(__row_id),
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (2)),
  "context" INTEGER REFERENCES "r_record_ref"(__row_id),
  "realm__state" INTEGER NOT NULL CHECK("realm__state" IN (0,1,2)),
  "realm" INTEGER REFERENCES "r_scope_realm"(__row_id),
  CHECK(("applicability__state"=2 AND "applicability" IS NOT NULL) OR ("applicability__state" IN (0,1) AND "applicability" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("realm__state"=2 AND "realm" IS NOT NULL) OR ("realm__state" IN (0,1) AND "realm" IS NULL))
) STRICT;

CREATE TABLE "r_scope_realm" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v18_alternatives" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v18_alternatives_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v18_alternatives"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_evidence_basis" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 6),
  v0 INTEGER REFERENCES "r_evidence_basis_v0"(__row_id),
  v1 INTEGER REFERENCES "r_evidence_basis_v1"(__row_id),
  v2 INTEGER REFERENCES "r_evidence_basis_v2"(__row_id),
  v3 INTEGER REFERENCES "r_evidence_basis_v3"(__row_id),
  v4 INTEGER REFERENCES "r_evidence_basis_v4"(__row_id),
  v5 INTEGER REFERENCES "r_evidence_basis_v5"(__row_id),
  v6 INTEGER REFERENCES "r_evidence_basis_v6"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL),
  CHECK(variant=6 OR v6 IS NULL),
  CHECK(variant!=6 OR v6 IS NOT NULL)
) STRICT;

CREATE TABLE "r_evidence_basis_v0" (
  __row_id INTEGER PRIMARY KEY,
  "note__state" INTEGER NOT NULL CHECK("note__state" IN (2)),
  "note" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("note__state"=2 AND "note" IS NOT NULL) OR ("note__state" IN (0,1) AND "note" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='author_decision')
) STRICT;

CREATE TABLE "r_evidence_basis_v1" (
  __row_id INTEGER PRIMARY KEY,
  "anchor__state" INTEGER NOT NULL CHECK("anchor__state" IN (2)),
  "anchor" INTEGER REFERENCES "r_record_ref"(__row_id),
  "verified__state" INTEGER NOT NULL CHECK("verified__state" IN (2)),
  "verified" INTEGER,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("anchor__state"=2 AND "anchor" IS NOT NULL) OR ("anchor__state" IN (0,1) AND "anchor" IS NULL)),
  CHECK(("verified__state"=2 AND "verified" IS NOT NULL) OR ("verified__state" IN (0,1) AND "verified" IS NULL)),
  CHECK("verified" IN (0,1)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='source_anchor')
) STRICT;

CREATE TABLE "r_evidence_basis_v2" (
  __row_id INTEGER PRIMARY KEY,
  "event__state" INTEGER NOT NULL CHECK("event__state" IN (2)),
  "event" INTEGER REFERENCES "r_record_ref"(__row_id),
  "slot__state" INTEGER NOT NULL CHECK("slot__state" IN (2)),
  "slot" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("event__state"=2 AND "event" IS NOT NULL) OR ("event__state" IN (0,1) AND "event" IS NULL)),
  CHECK(("slot__state"=2 AND "slot" IS NOT NULL) OR ("slot__state" IN (0,1) AND "slot" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='event_effect')
) STRICT;

CREATE TABLE "r_evidence_basis_v3" (
  __row_id INTEGER PRIMARY KEY,
  "start__state" INTEGER NOT NULL CHECK("start__state" IN (2)),
  "start" INTEGER REFERENCES "r_version_ref"(__row_id),
  "definition__state" INTEGER NOT NULL CHECK("definition__state" IN (2)),
  "definition" INTEGER REFERENCES "r_version_ref"(__row_id),
  "source_revision__state" INTEGER NOT NULL CHECK("source_revision__state" IN (2)),
  "source_revision" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("start__state"=2 AND "start" IS NOT NULL) OR ("start__state" IN (0,1) AND "start" IS NULL)),
  CHECK(("definition__state"=2 AND "definition" IS NOT NULL) OR ("definition__state" IN (0,1) AND "definition" IS NULL)),
  CHECK(("source_revision__state"=2 AND "source_revision" IS NOT NULL) OR ("source_revision__state" IN (0,1) AND "source_revision" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='instance_initialization')
) STRICT;

CREATE TABLE "r_evidence_basis_v4" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='imported_claim')
) STRICT;

CREATE TABLE "r_evidence_basis_v5" (
  __row_id INTEGER PRIMARY KEY,
  "chain__state" INTEGER NOT NULL CHECK("chain__state" IN (2)),
  "chain" INTEGER REFERENCES "r_evidence_basis_v5_chain"(__row_id),
  "evaluator__state" INTEGER NOT NULL CHECK("evaluator__state" IN (0,1,2)),
  "evaluator" INTEGER REFERENCES "r_evidence_basis_v5_evaluator"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("chain__state"=2 AND "chain" IS NOT NULL) OR ("chain__state" IN (0,1) AND "chain" IS NULL)),
  CHECK(("evaluator__state"=2 AND "evaluator" IS NOT NULL) OR ("evaluator__state" IN (0,1) AND "evaluator" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='derivation')
) STRICT;

CREATE TABLE "r_evidence_basis_v5_chain" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_evidence_basis_v5_chain_items" (owner INTEGER NOT NULL REFERENCES "r_evidence_basis_v5_chain"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_version_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_evidence_basis_v5_evaluator" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_evidence_basis_v6" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  "start__state" INTEGER NOT NULL CHECK("start__state" IN (2)),
  "start" INTEGER REFERENCES "r_version_ref"(__row_id),
  "definition__state" INTEGER NOT NULL CHECK("definition__state" IN (2)),
  "definition" INTEGER REFERENCES "r_version_ref"(__row_id),
  "source_revision__state" INTEGER NOT NULL CHECK("source_revision__state" IN (2)),
  "source_revision" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='instance_initialization'),
  CHECK(("start__state"=2 AND "start" IS NOT NULL) OR ("start__state" IN (0,1) AND "start" IS NULL)),
  CHECK(("definition__state"=2 AND "definition" IS NOT NULL) OR ("definition__state" IN (0,1) AND "definition" IS NULL)),
  CHECK(("source_revision__state"=2 AND "source_revision" IS NOT NULL) OR ("source_revision__state" IN (0,1) AND "source_revision" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v18_established_by" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_event_effect_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_event_effect_ref" (
  __row_id INTEGER PRIMARY KEY,
  "event__state" INTEGER NOT NULL CHECK("event__state" IN (2)),
  "event" INTEGER REFERENCES "r_record_ref"(__row_id),
  "slot__state" INTEGER NOT NULL CHECK("slot__state" IN (2)),
  "slot" TEXT,
  CHECK(("event__state"=2 AND "event" IS NOT NULL) OR ("event__state" IN (0,1) AND "event" IS NULL)),
  CHECK(("slot__state"=2 AND "slot" IS NOT NULL) OR ("slot__state" IN (0,1) AND "slot" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v19" (
  __row_id INTEGER PRIMARY KEY,
  "universe__state" INTEGER NOT NULL CHECK("universe__state" IN (2)),
  "universe" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" INTEGER REFERENCES "r_represented_context_kind"(__row_id),
  "parent__state" INTEGER NOT NULL CHECK("parent__state" IN (0,1,2)),
  "parent" INTEGER REFERENCES "r_payload_v19_parent"(__row_id),
  "chronology__state" INTEGER NOT NULL CHECK("chronology__state" IN (0,1,2)),
  "chronology" INTEGER REFERENCES "r_payload_v19_chronology"(__row_id),
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v19_labels"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("universe__state"=2 AND "universe" IS NOT NULL) OR ("universe__state" IN (0,1) AND "universe" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK(("parent__state"=2 AND "parent" IS NOT NULL) OR ("parent__state" IN (0,1) AND "parent" IS NULL)),
  CHECK(("chronology__state"=2 AND "chronology" IS NOT NULL) OR ("chronology__state" IN (0,1) AND "chronology" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='represented_context')
) STRICT;

CREATE TABLE "r_represented_context_kind" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 4),
  v0 INTEGER REFERENCES "r_represented_context_kind_v0"(__row_id),
  v1 INTEGER REFERENCES "r_represented_context_kind_v1"(__row_id),
  v2 INTEGER REFERENCES "r_represented_context_kind_v2"(__row_id),
  v3 INTEGER REFERENCES "r_represented_context_kind_v3"(__row_id),
  v4 INTEGER REFERENCES "r_represented_context_kind_v4"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL)
) STRICT;

CREATE TABLE "r_represented_context_kind_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='objective')
) STRICT;

CREATE TABLE "r_represented_context_kind_v1" (
  __row_id INTEGER PRIMARY KEY,
  "holder__state" INTEGER NOT NULL CHECK("holder__state" IN (2)),
  "holder" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("holder__state"=2 AND "holder" IS NOT NULL) OR ("holder__state" IN (0,1) AND "holder" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='character')
) STRICT;

CREATE TABLE "r_represented_context_kind_v2" (
  __row_id INTEGER PRIMARY KEY,
  "source__state" INTEGER NOT NULL CHECK("source__state" IN (2)),
  "source" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("source__state"=2 AND "source" IS NOT NULL) OR ("source__state" IN (0,1) AND "source" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='source')
) STRICT;

CREATE TABLE "r_represented_context_kind_v3" (
  __row_id INTEGER PRIMARY KEY,
  "narrator__state" INTEGER NOT NULL CHECK("narrator__state" IN (2)),
  "narrator" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("narrator__state"=2 AND "narrator" IS NOT NULL) OR ("narrator__state" IN (0,1) AND "narrator" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='narrator')
) STRICT;

CREATE TABLE "r_represented_context_kind_v4" (
  __row_id INTEGER PRIMARY KEY,
  "label__state" INTEGER NOT NULL CHECK("label__state" IN (2)),
  "label" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("label__state"=2 AND "label" IS NOT NULL) OR ("label__state" IN (0,1) AND "label" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='authored')
) STRICT;

CREATE TABLE "r_payload_v19_parent" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v19_chronology" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_chronology"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_chronology" (
  __row_id INTEGER PRIMARY KEY,
  "calendar__state" INTEGER NOT NULL CHECK("calendar__state" IN (2)),
  "calendar" TEXT,
  "system__state" INTEGER NOT NULL CHECK("system__state" IN (2)),
  "system" INTEGER REFERENCES "r_clock_system"(__row_id),
  "first_interaction__state" INTEGER NOT NULL CHECK("first_interaction__state" IN (2)),
  "first_interaction" TEXT,
  "current__state" INTEGER NOT NULL CHECK("current__state" IN (2)),
  "current" TEXT,
  CHECK(("calendar__state"=2 AND "calendar" IS NOT NULL) OR ("calendar__state" IN (0,1) AND "calendar" IS NULL)),
  CHECK(("system__state"=2 AND "system" IS NOT NULL) OR ("system__state" IN (0,1) AND "system" IS NULL)),
  CHECK(("first_interaction__state"=2 AND "first_interaction" IS NOT NULL) OR ("first_interaction__state" IN (0,1) AND "first_interaction" IS NULL)),
  CHECK(("current__state"=2 AND "current" IS NOT NULL) OR ("current__state" IN (0,1) AND "current" IS NULL))
) STRICT;

CREATE TABLE "r_clock_system" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_clock_system_v0"(__row_id),
  v1 INTEGER REFERENCES "r_clock_system_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_clock_system_v0" (
  __row_id INTEGER PRIMARY KEY,
  "offset_seconds__state" INTEGER NOT NULL CHECK("offset_seconds__state" IN (2)),
  "offset_seconds" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("offset_seconds__state"=2 AND "offset_seconds" IS NOT NULL) OR ("offset_seconds__state" IN (0,1) AND "offset_seconds" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='gregorian')
) STRICT;

CREATE TABLE "r_clock_system_v1" (
  __row_id INTEGER PRIMARY KEY,
  "tick_label__state" INTEGER NOT NULL CHECK("tick_label__state" IN (2)),
  "tick_label" TEXT,
  "ticks_per_month__state" INTEGER NOT NULL CHECK("ticks_per_month__state" IN (0,1,2)),
  "ticks_per_month" INTEGER REFERENCES "r_clock_system_v1_ticks_per_month"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("tick_label__state"=2 AND "tick_label" IS NOT NULL) OR ("tick_label__state" IN (0,1) AND "tick_label" IS NULL)),
  CHECK(("ticks_per_month__state"=2 AND "ticks_per_month" IS NOT NULL) OR ("ticks_per_month__state" IN (0,1) AND "ticks_per_month" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='fictional')
) STRICT;

CREATE TABLE "r_clock_system_v1_ticks_per_month" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v19_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v19_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v19_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v20" (
  __row_id INTEGER PRIMARY KEY,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_record_ref"(__row_id),
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" TEXT,
  "members__state" INTEGER NOT NULL CHECK("members__state" IN (2)),
  "members" INTEGER REFERENCES "r_payload_v20_members"(__row_id),
  "completeness__state" INTEGER NOT NULL CHECK("completeness__state" IN (2)),
  "completeness" INTEGER REFERENCES "r_completeness_kind"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("members__state"=2 AND "members" IS NOT NULL) OR ("members__state" IN (0,1) AND "members" IS NULL)),
  CHECK(("completeness__state"=2 AND "completeness" IS NOT NULL) OR ("completeness__state" IN (0,1) AND "completeness" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='completeness')
) STRICT;

CREATE TABLE "r_payload_v20_members" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v20_members_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v20_members"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_completeness_kind" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 INTEGER REFERENCES "r_completeness_kind_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_completeness_kind_v1" (
  __row_id INTEGER PRIMARY KEY,
  "observer_known__state" INTEGER NOT NULL CHECK("observer_known__state" IN (2)),
  "observer_known" INTEGER REFERENCES "r_completeness_kind_v1_observer_known"(__row_id),
  CHECK(("observer_known__state"=2 AND "observer_known" IS NOT NULL) OR ("observer_known__state" IN (0,1) AND "observer_known" IS NULL))
) STRICT;

CREATE TABLE "r_completeness_kind_v1_observer_known" (
  __row_id INTEGER PRIMARY KEY,
  "observer__state" INTEGER NOT NULL CHECK("observer__state" IN (2)),
  "observer" TEXT,
  CHECK(("observer__state"=2 AND "observer" IS NOT NULL) OR ("observer__state" IN (0,1) AND "observer" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v21" (
  __row_id INTEGER PRIMARY KEY,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "area__state" INTEGER NOT NULL CHECK("area__state" IN (2)),
  "area" INTEGER REFERENCES "r_boundary_area"(__row_id),
  "mode__state" INTEGER NOT NULL CHECK("mode__state" IN (2)),
  "mode" INTEGER REFERENCES "r_boundary_mode"(__row_id),
  "constraints__state" INTEGER NOT NULL CHECK("constraints__state" IN (0,2)),
  "constraints" INTEGER REFERENCES "r_payload_v21_constraints"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("area__state"=2 AND "area" IS NOT NULL) OR ("area__state" IN (0,1) AND "area" IS NULL)),
  CHECK(("mode__state"=2 AND "mode" IS NOT NULL) OR ("mode__state" IN (0,1) AND "mode" IS NULL)),
  CHECK(("constraints__state"=2 AND "constraints" IS NOT NULL) OR ("constraints__state" IN (0,1) AND "constraints" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='boundary')
) STRICT;

CREATE TABLE "r_boundary_area" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 2),
  v0 INTEGER REFERENCES "r_boundary_area_v0"(__row_id),
  v1 INTEGER REFERENCES "r_boundary_area_v1"(__row_id),
  v2 INTEGER REFERENCES "r_boundary_area_v2"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL)
) STRICT;

CREATE TABLE "r_boundary_area_v0" (
  __row_id INTEGER PRIMARY KEY,
  "universe__state" INTEGER NOT NULL CHECK("universe__state" IN (0,1,2)),
  "universe" INTEGER REFERENCES "r_boundary_area_v0_universe"(__row_id),
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("universe__state"=2 AND "universe" IS NOT NULL) OR ("universe__state" IN (0,1) AND "universe" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record')
) STRICT;

CREATE TABLE "r_boundary_area_v0_universe" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_boundary_area_v1" (
  __row_id INTEGER PRIMARY KEY,
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" TEXT,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (0,1,2)),
  "subject" INTEGER REFERENCES "r_boundary_area_v1_subject"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='predicate')
) STRICT;

CREATE TABLE "r_boundary_area_v1_subject" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_boundary_area_v2" (
  __row_id INTEGER PRIMARY KEY,
  "entity_type__state" INTEGER NOT NULL CHECK("entity_type__state" IN (2)),
  "entity_type" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("entity_type__state"=2 AND "entity_type" IS NOT NULL) OR ("entity_type__state" IN (0,1) AND "entity_type" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='category')
) STRICT;

CREATE TABLE "r_boundary_mode" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 5),
  v0 TEXT,
  v1 TEXT,
  v2 TEXT,
  v3 TEXT,
  v4 TEXT,
  v5 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL)
) STRICT;

CREATE TABLE "r_payload_v21_constraints" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v21_constraints_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v21_constraints"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_expr" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 14),
  v0 INTEGER REFERENCES "r_expr_v0"(__row_id),
  v1 INTEGER REFERENCES "r_expr_v1"(__row_id),
  v2 INTEGER REFERENCES "r_expr_v2"(__row_id),
  v3 INTEGER REFERENCES "r_expr_v3"(__row_id),
  v4 INTEGER REFERENCES "r_expr_v4"(__row_id),
  v5 INTEGER REFERENCES "r_expr_v5"(__row_id),
  v6 INTEGER REFERENCES "r_expr_v6"(__row_id),
  v7 INTEGER REFERENCES "r_expr_v7"(__row_id),
  v8 INTEGER REFERENCES "r_expr_v8"(__row_id),
  v9 INTEGER REFERENCES "r_expr_v9"(__row_id),
  v10 INTEGER REFERENCES "r_expr_v10"(__row_id),
  v11 INTEGER REFERENCES "r_expr_v11"(__row_id),
  v12 INTEGER REFERENCES "r_expr_v12"(__row_id),
  v13 INTEGER REFERENCES "r_expr_v13"(__row_id),
  v14 INTEGER REFERENCES "r_expr_v14"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL),
  CHECK(variant=6 OR v6 IS NULL),
  CHECK(variant!=6 OR v6 IS NOT NULL),
  CHECK(variant=7 OR v7 IS NULL),
  CHECK(variant!=7 OR v7 IS NOT NULL),
  CHECK(variant=8 OR v8 IS NULL),
  CHECK(variant!=8 OR v8 IS NOT NULL),
  CHECK(variant=9 OR v9 IS NULL),
  CHECK(variant!=9 OR v9 IS NOT NULL),
  CHECK(variant=10 OR v10 IS NULL),
  CHECK(variant!=10 OR v10 IS NOT NULL),
  CHECK(variant=11 OR v11 IS NULL),
  CHECK(variant!=11 OR v11 IS NOT NULL),
  CHECK(variant=12 OR v12 IS NULL),
  CHECK(variant!=12 OR v12 IS NOT NULL),
  CHECK(variant=13 OR v13 IS NULL),
  CHECK(variant!=13 OR v13 IS NOT NULL),
  CHECK(variant=14 OR v14 IS NULL),
  CHECK(variant!=14 OR v14 IS NOT NULL)
) STRICT;

CREATE TABLE "r_expr_v0" (
  __row_id INTEGER PRIMARY KEY,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_operand"(__row_id),
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" TEXT,
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (2)),
  "context" INTEGER REFERENCES "r_operand"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='no_opposing_evidence')
) STRICT;

CREATE TABLE "r_operand" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 5),
  v0 INTEGER REFERENCES "r_operand_v0"(__row_id),
  v1 INTEGER REFERENCES "r_operand_v1"(__row_id),
  v2 INTEGER REFERENCES "r_operand_v2"(__row_id),
  v3 INTEGER REFERENCES "r_operand_v3"(__row_id),
  v4 INTEGER REFERENCES "r_operand_v4"(__row_id),
  v5 INTEGER REFERENCES "r_operand_v5"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL)
) STRICT;

CREATE TABLE "r_operand_v0" (
  __row_id INTEGER PRIMARY KEY,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='variable')
) STRICT;

CREATE TABLE "r_operand_v1" (
  __row_id INTEGER PRIMARY KEY,
  "ref__state" INTEGER NOT NULL CHECK("ref__state" IN (2)),
  "ref" INTEGER REFERENCES "r_record_ref"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("ref__state"=2 AND "ref" IS NOT NULL) OR ("ref__state" IN (0,1) AND "ref" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record')
) STRICT;

CREATE TABLE "r_operand_v2" (
  __row_id INTEGER PRIMARY KEY,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='value')
) STRICT;

CREATE TABLE "r_operand_v3" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='frame_time')
) STRICT;

CREATE TABLE "r_operand_v4" (
  __row_id INTEGER PRIMARY KEY,
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='event_participant')
) STRICT;

CREATE TABLE "r_operand_v5" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='event_ref')
) STRICT;

CREATE TABLE "r_expr_v1" (
  __row_id INTEGER PRIMARY KEY,
  "holder__state" INTEGER NOT NULL CHECK("holder__state" IN (2)),
  "holder" INTEGER REFERENCES "r_record_ref"(__row_id),
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" INTEGER REFERENCES "r_record_ref"(__row_id),
  "attitude__state" INTEGER NOT NULL CHECK("attitude__state" IN (2)),
  "attitude" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("holder__state"=2 AND "holder" IS NOT NULL) OR ("holder__state" IN (0,1) AND "holder" IS NULL)),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("attitude__state"=2 AND "attitude" IS NOT NULL) OR ("attitude__state" IN (0,1) AND "attitude" IS NULL)),
  CHECK("attitude" IN ('believes','suspects','rejects','remembers','knows')),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='attitude')
) STRICT;

CREATE TABLE "r_expr_v2" (
  __row_id INTEGER PRIMARY KEY,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK("value" IN (0,1)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='lit')
) STRICT;

CREATE TABLE "r_expr_v3" (
  __row_id INTEGER PRIMARY KEY,
  "expr__state" INTEGER NOT NULL CHECK("expr__state" IN (2)),
  "expr" INTEGER REFERENCES "r_expr"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("expr__state"=2 AND "expr" IS NOT NULL) OR ("expr__state" IN (0,1) AND "expr" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='not')
) STRICT;

CREATE TABLE "r_expr_v4" (
  __row_id INTEGER PRIMARY KEY,
  "exprs__state" INTEGER NOT NULL CHECK("exprs__state" IN (2)),
  "exprs" INTEGER REFERENCES "r_expr_v4_exprs"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("exprs__state"=2 AND "exprs" IS NOT NULL) OR ("exprs__state" IN (0,1) AND "exprs" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='all')
) STRICT;

CREATE TABLE "r_expr_v4_exprs" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_expr_v4_exprs_items" (owner INTEGER NOT NULL REFERENCES "r_expr_v4_exprs"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_expr_v5" (
  __row_id INTEGER PRIMARY KEY,
  "exprs__state" INTEGER NOT NULL CHECK("exprs__state" IN (2)),
  "exprs" INTEGER REFERENCES "r_expr_v5_exprs"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("exprs__state"=2 AND "exprs" IS NOT NULL) OR ("exprs__state" IN (0,1) AND "exprs" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='any')
) STRICT;

CREATE TABLE "r_expr_v5_exprs" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_expr_v5_exprs_items" (owner INTEGER NOT NULL REFERENCES "r_expr_v5_exprs"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_expr_v6" (
  __row_id INTEGER PRIMARY KEY,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_operand"(__row_id),
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" TEXT,
  "roles__state" INTEGER NOT NULL CHECK("roles__state" IN (0,2)),
  "roles" INTEGER REFERENCES "r_expr_v6_roles"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (0,1,2)),
  "value" INTEGER REFERENCES "r_expr_v6_value"(__row_id),
  "polarity__state" INTEGER NOT NULL CHECK("polarity__state" IN (2)),
  "polarity" TEXT,
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (0,1,2)),
  "context" INTEGER REFERENCES "r_expr_v6_context"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("roles__state"=2 AND "roles" IS NOT NULL) OR ("roles__state" IN (0,1) AND "roles" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("polarity__state"=2 AND "polarity" IS NOT NULL) OR ("polarity__state" IN (0,1) AND "polarity" IS NULL)),
  CHECK("polarity" IN ('support','refutation')),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='claim')
) STRICT;

CREATE TABLE "r_expr_v6_roles" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_expr_v6_roles_items" (owner INTEGER NOT NULL REFERENCES "r_expr_v6_roles"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr_v6_roles_item"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_expr_v6_roles_item" (
  __row_id INTEGER PRIMARY KEY,
  "0__state" INTEGER NOT NULL CHECK("0__state" IN (2)),
  "0" TEXT,
  "1__state" INTEGER NOT NULL CHECK("1__state" IN (2)),
  "1" INTEGER REFERENCES "r_operand"(__row_id),
  CHECK(("0__state"=2 AND "0" IS NOT NULL) OR ("0__state" IN (0,1) AND "0" IS NULL)),
  CHECK(("1__state"=2 AND "1" IS NOT NULL) OR ("1__state" IN (0,1) AND "1" IS NULL))
) STRICT;

CREATE TABLE "r_expr_v6_value" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_operand"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_expr_v6_context" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_operand"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_expr_v7" (
  __row_id INTEGER PRIMARY KEY,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_operand"(__row_id),
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" TEXT,
  "roles__state" INTEGER NOT NULL CHECK("roles__state" IN (0,2)),
  "roles" INTEGER REFERENCES "r_expr_v7_roles"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (0,1,2)),
  "value" INTEGER REFERENCES "r_expr_v7_value"(__row_id),
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (0,1,2)),
  "context" INTEGER REFERENCES "r_expr_v7_context"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("roles__state"=2 AND "roles" IS NOT NULL) OR ("roles__state" IN (0,1) AND "roles" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='negated_claim')
) STRICT;

CREATE TABLE "r_expr_v7_roles" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_expr_v7_roles_items" (owner INTEGER NOT NULL REFERENCES "r_expr_v7_roles"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr_v7_roles_item"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_expr_v7_roles_item" (
  __row_id INTEGER PRIMARY KEY,
  "0__state" INTEGER NOT NULL CHECK("0__state" IN (2)),
  "0" TEXT,
  "1__state" INTEGER NOT NULL CHECK("1__state" IN (2)),
  "1" INTEGER REFERENCES "r_operand"(__row_id),
  CHECK(("0__state"=2 AND "0" IS NOT NULL) OR ("0__state" IN (0,1) AND "0" IS NULL)),
  CHECK(("1__state"=2 AND "1" IS NOT NULL) OR ("1__state" IN (0,1) AND "1" IS NULL))
) STRICT;

CREATE TABLE "r_expr_v7_value" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_operand"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_expr_v7_context" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_operand"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_expr_v8" (
  __row_id INTEGER PRIMARY KEY,
  "left__state" INTEGER NOT NULL CHECK("left__state" IN (2)),
  "left" INTEGER REFERENCES "r_operand"(__row_id),
  "op__state" INTEGER NOT NULL CHECK("op__state" IN (2)),
  "op" TEXT,
  "right__state" INTEGER NOT NULL CHECK("right__state" IN (2)),
  "right" INTEGER REFERENCES "r_operand"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("left__state"=2 AND "left" IS NOT NULL) OR ("left__state" IN (0,1) AND "left" IS NULL)),
  CHECK(("op__state"=2 AND "op" IS NOT NULL) OR ("op__state" IN (0,1) AND "op" IS NULL)),
  CHECK("op" IN ('eq','neq','lt','lt_eq','gt','gt_eq')),
  CHECK(("right__state"=2 AND "right" IS NOT NULL) OR ("right__state" IN (0,1) AND "right" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='compare')
) STRICT;

CREATE TABLE "r_expr_v9" (
  __row_id INTEGER PRIMARY KEY,
  "left__state" INTEGER NOT NULL CHECK("left__state" IN (2)),
  "left" INTEGER REFERENCES "r_operand"(__row_id),
  "relation__state" INTEGER NOT NULL CHECK("relation__state" IN (2)),
  "relation" INTEGER REFERENCES "r_temporal_relation"(__row_id),
  "right__state" INTEGER NOT NULL CHECK("right__state" IN (2)),
  "right" INTEGER REFERENCES "r_operand"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("left__state"=2 AND "left" IS NOT NULL) OR ("left__state" IN (0,1) AND "left" IS NULL)),
  CHECK(("relation__state"=2 AND "relation" IS NOT NULL) OR ("relation__state" IN (0,1) AND "relation" IS NULL)),
  CHECK(("right__state"=2 AND "right" IS NOT NULL) OR ("right__state" IN (0,1) AND "right" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='temporal')
) STRICT;

CREATE TABLE "r_expr_v10" (
  __row_id INTEGER PRIMARY KEY,
  "element__state" INTEGER NOT NULL CHECK("element__state" IN (2)),
  "element" INTEGER REFERENCES "r_operand"(__row_id),
  "collection__state" INTEGER NOT NULL CHECK("collection__state" IN (2)),
  "collection" INTEGER REFERENCES "r_operand"(__row_id),
  "complete__state" INTEGER NOT NULL CHECK("complete__state" IN (0,1,2)),
  "complete" INTEGER REFERENCES "r_expr_v10_complete"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("element__state"=2 AND "element" IS NOT NULL) OR ("element__state" IN (0,1) AND "element" IS NULL)),
  CHECK(("collection__state"=2 AND "collection" IS NOT NULL) OR ("collection__state" IN (0,1) AND "collection" IS NULL)),
  CHECK(("complete__state"=2 AND "complete" IS NOT NULL) OR ("complete__state" IN (0,1) AND "complete" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='membership')
) STRICT;

CREATE TABLE "r_expr_v10_complete" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_expr_v11" (
  __row_id INTEGER PRIMARY KEY,
  "collection__state" INTEGER NOT NULL CHECK("collection__state" IN (2)),
  "collection" INTEGER REFERENCES "r_operand"(__row_id),
  "op__state" INTEGER NOT NULL CHECK("op__state" IN (2)),
  "op" TEXT,
  "count__state" INTEGER NOT NULL CHECK("count__state" IN (2)),
  "count" INTEGER REFERENCES "r_value"(__row_id),
  "complete__state" INTEGER NOT NULL CHECK("complete__state" IN (0,1,2)),
  "complete" INTEGER REFERENCES "r_expr_v11_complete"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("collection__state"=2 AND "collection" IS NOT NULL) OR ("collection__state" IN (0,1) AND "collection" IS NULL)),
  CHECK(("op__state"=2 AND "op" IS NOT NULL) OR ("op__state" IN (0,1) AND "op" IS NULL)),
  CHECK("op" IN ('eq','neq','lt','lt_eq','gt','gt_eq')),
  CHECK(("count__state"=2 AND "count" IS NOT NULL) OR ("count__state" IN (0,1) AND "count" IS NULL)),
  CHECK(("complete__state"=2 AND "complete" IS NOT NULL) OR ("complete__state" IN (0,1) AND "complete" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='cardinality')
) STRICT;

CREATE TABLE "r_expr_v11_complete" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_expr_v12" (
  __row_id INTEGER PRIMARY KEY,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_operand"(__row_id),
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" TEXT,
  "roles__state" INTEGER NOT NULL CHECK("roles__state" IN (0,2)),
  "roles" INTEGER REFERENCES "r_expr_v12_roles"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (0,1,2)),
  "value" INTEGER REFERENCES "r_expr_v12_value"(__row_id),
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (0,1,2)),
  "context" INTEGER REFERENCES "r_expr_v12_context"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("roles__state"=2 AND "roles" IS NOT NULL) OR ("roles__state" IN (0,1) AND "roles" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='existence')
) STRICT;

CREATE TABLE "r_expr_v12_roles" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_expr_v12_roles_items" (owner INTEGER NOT NULL REFERENCES "r_expr_v12_roles"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr_v12_roles_item"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_expr_v12_roles_item" (
  __row_id INTEGER PRIMARY KEY,
  "0__state" INTEGER NOT NULL CHECK("0__state" IN (2)),
  "0" TEXT,
  "1__state" INTEGER NOT NULL CHECK("1__state" IN (2)),
  "1" INTEGER REFERENCES "r_operand"(__row_id),
  CHECK(("0__state"=2 AND "0" IS NOT NULL) OR ("0__state" IN (0,1) AND "0" IS NULL)),
  CHECK(("1__state"=2 AND "1" IS NOT NULL) OR ("1__state" IN (0,1) AND "1" IS NULL))
) STRICT;

CREATE TABLE "r_expr_v12_value" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_operand"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_expr_v12_context" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_operand"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_expr_v13" (
  __row_id INTEGER PRIMARY KEY,
  "variable__state" INTEGER NOT NULL CHECK("variable__state" IN (2)),
  "variable" TEXT,
  "over__state" INTEGER NOT NULL CHECK("over__state" IN (2)),
  "over" INTEGER REFERENCES "r_operand"(__row_id),
  "complete__state" INTEGER NOT NULL CHECK("complete__state" IN (2)),
  "complete" INTEGER,
  "quantifier__state" INTEGER NOT NULL CHECK("quantifier__state" IN (2)),
  "quantifier" TEXT,
  "body__state" INTEGER NOT NULL CHECK("body__state" IN (2)),
  "body" INTEGER REFERENCES "r_expr"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("variable__state"=2 AND "variable" IS NOT NULL) OR ("variable__state" IN (0,1) AND "variable" IS NULL)),
  CHECK(("over__state"=2 AND "over" IS NOT NULL) OR ("over__state" IN (0,1) AND "over" IS NULL)),
  CHECK(("complete__state"=2 AND "complete" IS NOT NULL) OR ("complete__state" IN (0,1) AND "complete" IS NULL)),
  CHECK("complete" IN (0,1)),
  CHECK(("quantifier__state"=2 AND "quantifier" IS NOT NULL) OR ("quantifier__state" IN (0,1) AND "quantifier" IS NULL)),
  CHECK("quantifier" IN ('for_all','exists')),
  CHECK(("body__state"=2 AND "body" IS NOT NULL) OR ("body__state" IN (0,1) AND "body" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='quantify')
) STRICT;

CREATE TABLE "r_expr_v14" (
  __row_id INTEGER PRIMARY KEY,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_operand"(__row_id),
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" TEXT,
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  "participant__state" INTEGER NOT NULL CHECK("participant__state" IN (2)),
  "participant" INTEGER REFERENCES "r_operand"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("participant__state"=2 AND "participant" IS NOT NULL) OR ("participant__state" IN (0,1) AND "participant" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='role_holds')
) STRICT;

CREATE TABLE "r_payload_v22" (
  __row_id INTEGER PRIMARY KEY,
  "knowledgePolicy__state" INTEGER NOT NULL CHECK("knowledgePolicy__state" IN (0,1,2)),
  "knowledgePolicy" INTEGER REFERENCES "r_payload_v22_knowledge_policy"(__row_id),
  "channelChronology__state" INTEGER NOT NULL CHECK("channelChronology__state" IN (0,1,2)),
  "channelChronology" INTEGER REFERENCES "r_payload_v22_channel_chronology"(__row_id),
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v22_labels"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" INTEGER REFERENCES "r_rule_kind"(__row_id),
  "commitPolicy__state" INTEGER NOT NULL CHECK("commitPolicy__state" IN (2)),
  "commitPolicy" INTEGER REFERENCES "r_commit_policy"(__row_id),
  "applicability__state" INTEGER NOT NULL CHECK("applicability__state" IN (2)),
  "applicability" INTEGER REFERENCES "r_applicability"(__row_id),
  "subjectTypes__state" INTEGER NOT NULL CHECK("subjectTypes__state" IN (0,2)),
  "subjectTypes" INTEGER REFERENCES "r_payload_v22_subject_types"(__row_id),
  "targetPredicates__state" INTEGER NOT NULL CHECK("targetPredicates__state" IN (2)),
  "targetPredicates" INTEGER REFERENCES "r_payload_v22_target_predicates"(__row_id),
  "expression__state" INTEGER NOT NULL CHECK("expression__state" IN (2)),
  "expression" INTEGER REFERENCES "r_expr"(__row_id),
  "capabilities__state" INTEGER NOT NULL CHECK("capabilities__state" IN (2)),
  "capabilities" INTEGER REFERENCES "r_payload_v22_capabilities"(__row_id),
  "executable__state" INTEGER NOT NULL CHECK("executable__state" IN (2)),
  "executable" INTEGER,
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("knowledgePolicy__state"=2 AND "knowledgePolicy" IS NOT NULL) OR ("knowledgePolicy__state" IN (0,1) AND "knowledgePolicy" IS NULL)),
  CHECK(("channelChronology__state"=2 AND "channelChronology" IS NOT NULL) OR ("channelChronology__state" IN (0,1) AND "channelChronology" IS NULL)),
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK(("commitPolicy__state"=2 AND "commitPolicy" IS NOT NULL) OR ("commitPolicy__state" IN (0,1) AND "commitPolicy" IS NULL)),
  CHECK(("applicability__state"=2 AND "applicability" IS NOT NULL) OR ("applicability__state" IN (0,1) AND "applicability" IS NULL)),
  CHECK(("subjectTypes__state"=2 AND "subjectTypes" IS NOT NULL) OR ("subjectTypes__state" IN (0,1) AND "subjectTypes" IS NULL)),
  CHECK(("targetPredicates__state"=2 AND "targetPredicates" IS NOT NULL) OR ("targetPredicates__state" IN (0,1) AND "targetPredicates" IS NULL)),
  CHECK(("expression__state"=2 AND "expression" IS NOT NULL) OR ("expression__state" IN (0,1) AND "expression" IS NULL)),
  CHECK(("capabilities__state"=2 AND "capabilities" IS NOT NULL) OR ("capabilities__state" IN (0,1) AND "capabilities" IS NULL)),
  CHECK(("executable__state"=2 AND "executable" IS NOT NULL) OR ("executable__state" IN (0,1) AND "executable" IS NULL)),
  CHECK("executable" IN (0,1)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='rule')
) STRICT;

CREATE TABLE "r_payload_v22_knowledge_policy" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_knowledge_policy"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_knowledge_policy" (
  __row_id INTEGER PRIMARY KEY,
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (2)),
  "context" INTEGER REFERENCES "r_record_ref"(__row_id),
  "mode__state" INTEGER NOT NULL CHECK("mode__state" IN (2)),
  "mode" TEXT,
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("mode__state"=2 AND "mode" IS NOT NULL) OR ("mode__state" IN (0,1) AND "mode" IS NULL)),
  CHECK("mode" IN ('author_established','justified'))
) STRICT;

CREATE TABLE "r_payload_v22_channel_chronology" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_channel_chronology"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_channel_chronology" (
  __row_id INTEGER PRIMARY KEY,
  "channel__state" INTEGER NOT NULL CHECK("channel__state" IN (2)),
  "channel" TEXT,
  "forwardOnly__state" INTEGER NOT NULL CHECK("forwardOnly__state" IN (2)),
  "forwardOnly" INTEGER,
  "minimumDelay__state" INTEGER NOT NULL CHECK("minimumDelay__state" IN (0,1,2)),
  "minimumDelay" INTEGER REFERENCES "r_channel_chronology_minimum_delay"(__row_id),
  "maximumDelay__state" INTEGER NOT NULL CHECK("maximumDelay__state" IN (0,1,2)),
  "maximumDelay" INTEGER REFERENCES "r_channel_chronology_maximum_delay"(__row_id),
  CHECK(("channel__state"=2 AND "channel" IS NOT NULL) OR ("channel__state" IN (0,1) AND "channel" IS NULL)),
  CHECK(("forwardOnly__state"=2 AND "forwardOnly" IS NOT NULL) OR ("forwardOnly__state" IN (0,1) AND "forwardOnly" IS NULL)),
  CHECK("forwardOnly" IN (0,1)),
  CHECK(("minimumDelay__state"=2 AND "minimumDelay" IS NOT NULL) OR ("minimumDelay__state" IN (0,1) AND "minimumDelay" IS NULL)),
  CHECK(("maximumDelay__state"=2 AND "maximumDelay" IS NOT NULL) OR ("maximumDelay__state" IN (0,1) AND "maximumDelay" IS NULL))
) STRICT;

CREATE TABLE "r_channel_chronology_minimum_delay" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_channel_chronology_maximum_delay" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v22_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v22_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v22_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_rule_kind" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 6),
  v0 TEXT,
  v1 TEXT,
  v2 TEXT,
  v3 TEXT,
  v4 TEXT,
  v5 TEXT,
  v6 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL),
  CHECK(variant=6 OR v6 IS NULL),
  CHECK(variant!=6 OR v6 IS NOT NULL)
) STRICT;

CREATE TABLE "r_commit_policy" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 5),
  v0 TEXT,
  v1 TEXT,
  v2 TEXT,
  v3 TEXT,
  v4 TEXT,
  v5 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL)
) STRICT;

CREATE TABLE "r_payload_v22_subject_types" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v22_subject_types_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v22_subject_types"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v22_target_predicates" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v22_target_predicates_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v22_target_predicates"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v22_capabilities" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v22_capabilities_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v22_capabilities"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v23" (
  __row_id INTEGER PRIMARY KEY,
  "rule__state" INTEGER NOT NULL CHECK("rule__state" IN (2)),
  "rule" INTEGER REFERENCES "r_record_ref"(__row_id),
  "ruleVersion__state" INTEGER NOT NULL CHECK("ruleVersion__state" IN (0,1,2)),
  "ruleVersion" INTEGER REFERENCES "r_payload_v23_rule_version"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "authorizingDecision__state" INTEGER NOT NULL CHECK("authorizingDecision__state" IN (2)),
  "authorizingDecision" INTEGER REFERENCES "r_record_ref"(__row_id),
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("rule__state"=2 AND "rule" IS NOT NULL) OR ("rule__state" IN (0,1) AND "rule" IS NULL)),
  CHECK(("ruleVersion__state"=2 AND "ruleVersion" IS NOT NULL) OR ("ruleVersion__state" IN (0,1) AND "ruleVersion" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("authorizingDecision__state"=2 AND "authorizingDecision" IS NOT NULL) OR ("authorizingDecision__state" IN (0,1) AND "authorizingDecision" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='exception')
) STRICT;

CREATE TABLE "r_payload_v23_rule_version" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v24" (
  __row_id INTEGER PRIMARY KEY,
  "occurrence__state" INTEGER NOT NULL CHECK("occurrence__state" IN (2)),
  "occurrence" INTEGER REFERENCES "r_occurrence_mode"(__row_id),
  "action__state" INTEGER NOT NULL CHECK("action__state" IN (0,1,2)),
  "action" INTEGER REFERENCES "r_payload_v24_action"(__row_id),
  "worlds__state" INTEGER NOT NULL CHECK("worlds__state" IN (0,2)),
  "worlds" INTEGER REFERENCES "r_payload_v24_worlds"(__row_id),
  "region__state" INTEGER NOT NULL CHECK("region__state" IN (0,1,2)),
  "region" INTEGER REFERENCES "r_payload_v24_region"(__row_id),
  "time__state" INTEGER NOT NULL CHECK("time__state" IN (2)),
  "time" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "sequence__state" INTEGER NOT NULL CHECK("sequence__state" IN (0,1,2)),
  "sequence" INTEGER REFERENCES "r_payload_v24_sequence"(__row_id),
  "occurrenceId__state" INTEGER NOT NULL CHECK("occurrenceId__state" IN (0,1,2)),
  "occurrenceId" INTEGER REFERENCES "r_payload_v24_occurrence_id"(__row_id),
  "participants__state" INTEGER NOT NULL CHECK("participants__state" IN (2)),
  "participants" INTEGER REFERENCES "r_payload_v24_participants"(__row_id),
  "preconditions__state" INTEGER NOT NULL CHECK("preconditions__state" IN (0,2)),
  "preconditions" INTEGER REFERENCES "r_payload_v24_preconditions"(__row_id),
  "effects__state" INTEGER NOT NULL CHECK("effects__state" IN (0,2)),
  "effects" INTEGER REFERENCES "r_payload_v24_effects"(__row_id),
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v24_labels"(__row_id),
  "expansionVersion__state" INTEGER NOT NULL CHECK("expansionVersion__state" IN (0,1,2)),
  "expansionVersion" INTEGER REFERENCES "r_payload_v24_expansion_version"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("occurrence__state"=2 AND "occurrence" IS NOT NULL) OR ("occurrence__state" IN (0,1) AND "occurrence" IS NULL)),
  CHECK(("action__state"=2 AND "action" IS NOT NULL) OR ("action__state" IN (0,1) AND "action" IS NULL)),
  CHECK(("worlds__state"=2 AND "worlds" IS NOT NULL) OR ("worlds__state" IN (0,1) AND "worlds" IS NULL)),
  CHECK(("region__state"=2 AND "region" IS NOT NULL) OR ("region__state" IN (0,1) AND "region" IS NULL)),
  CHECK(("time__state"=2 AND "time" IS NOT NULL) OR ("time__state" IN (0,1) AND "time" IS NULL)),
  CHECK(("sequence__state"=2 AND "sequence" IS NOT NULL) OR ("sequence__state" IN (0,1) AND "sequence" IS NULL)),
  CHECK(("occurrenceId__state"=2 AND "occurrenceId" IS NOT NULL) OR ("occurrenceId__state" IN (0,1) AND "occurrenceId" IS NULL)),
  CHECK(("participants__state"=2 AND "participants" IS NOT NULL) OR ("participants__state" IN (0,1) AND "participants" IS NULL)),
  CHECK(("preconditions__state"=2 AND "preconditions" IS NOT NULL) OR ("preconditions__state" IN (0,1) AND "preconditions" IS NULL)),
  CHECK(("effects__state"=2 AND "effects" IS NOT NULL) OR ("effects__state" IN (0,1) AND "effects" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("expansionVersion__state"=2 AND "expansionVersion" IS NOT NULL) OR ("expansionVersion__state" IN (0,1) AND "expansionVersion" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='event')
) STRICT;

CREATE TABLE "r_occurrence_mode" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 INTEGER REFERENCES "r_occurrence_mode_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_occurrence_mode_v1" (
  __row_id INTEGER PRIMARY KEY,
  "descriptive__state" INTEGER NOT NULL CHECK("descriptive__state" IN (2)),
  "descriptive" INTEGER REFERENCES "r_occurrence_mode_v1_descriptive"(__row_id),
  CHECK(("descriptive__state"=2 AND "descriptive" IS NOT NULL) OR ("descriptive__state" IN (0,1) AND "descriptive" IS NULL))
) STRICT;

CREATE TABLE "r_occurrence_mode_v1_descriptive" (
  __row_id INTEGER PRIMARY KEY,
  "label__state" INTEGER NOT NULL CHECK("label__state" IN (2)),
  "label" TEXT,
  CHECK(("label__state"=2 AND "label" IS NOT NULL) OR ("label__state" IN (0,1) AND "label" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v24_action" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v24_worlds" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v24_worlds_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v24_worlds"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v24_region" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v24_sequence" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v24_occurrence_id" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v24_participants" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v24_participants_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v24_participants"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_event_participant"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_event_participant" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v24_preconditions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v24_preconditions_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v24_preconditions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v24_effects" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v24_effects_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v24_effects"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_entity_effect"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_entity_effect" (
  __row_id INTEGER PRIMARY KEY,
  "slot__state" INTEGER NOT NULL CHECK("slot__state" IN (2)),
  "slot" TEXT,
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" INTEGER REFERENCES "r_record_ref"(__row_id),
  "polarity__state" INTEGER NOT NULL CHECK("polarity__state" IN (2)),
  "polarity" TEXT,
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "order__state" INTEGER NOT NULL CHECK("order__state" IN (2)),
  "order" TEXT,
  CHECK(("slot__state"=2 AND "slot" IS NOT NULL) OR ("slot__state" IN (0,1) AND "slot" IS NULL)),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("polarity__state"=2 AND "polarity" IS NOT NULL) OR ("polarity__state" IN (0,1) AND "polarity" IS NULL)),
  CHECK("polarity" IN ('support','refutation')),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("order__state"=2 AND "order" IS NOT NULL) OR ("order__state" IN (0,1) AND "order" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v24_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v24_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v24_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v24_expansion_version" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v25" (
  __row_id INTEGER PRIMARY KEY,
  "item__state" INTEGER NOT NULL CHECK("item__state" IN (2)),
  "item" INTEGER REFERENCES "r_record_ref"(__row_id),
  "holderPredicate__state" INTEGER NOT NULL CHECK("holderPredicate__state" IN (2)),
  "holderPredicate" INTEGER REFERENCES "r_record_ref"(__row_id),
  "powerPredicate__state" INTEGER NOT NULL CHECK("powerPredicate__state" IN (2)),
  "powerPredicate" INTEGER REFERENCES "r_record_ref"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("item__state"=2 AND "item" IS NOT NULL) OR ("item__state" IN (0,1) AND "item" IS NULL)),
  CHECK(("holderPredicate__state"=2 AND "holderPredicate" IS NOT NULL) OR ("holderPredicate__state" IN (0,1) AND "holderPredicate" IS NULL)),
  CHECK(("powerPredicate__state"=2 AND "powerPredicate" IS NOT NULL) OR ("powerPredicate__state" IN (0,1) AND "powerPredicate" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='item_power')
) STRICT;

CREATE TABLE "r_payload_v26" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_payload_v26_labels"(__row_id),
  "requirements__state" INTEGER NOT NULL CHECK("requirements__state" IN (2)),
  "requirements" INTEGER REFERENCES "r_payload_v26_requirements"(__row_id),
  "consequenceContract__state" INTEGER NOT NULL CHECK("consequenceContract__state" IN (0,2)),
  "consequenceContract" INTEGER REFERENCES "r_consequence_contract"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("requirements__state"=2 AND "requirements" IS NOT NULL) OR ("requirements__state" IN (0,1) AND "requirements" IS NULL)),
  CHECK(("consequenceContract__state"=2 AND "consequenceContract" IS NOT NULL) OR ("consequenceContract__state" IN (0,1) AND "consequenceContract" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='action_definition')
) STRICT;

CREATE TABLE "r_payload_v26_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v26_labels_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v26_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_payload_v26_requirements" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v26_requirements_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v26_requirements"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_attribute_requirement"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_attribute_requirement" (
  __row_id INTEGER PRIMARY KEY,
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" INTEGER REFERENCES "r_record_ref"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL))
) STRICT;

CREATE TABLE "r_consequence_contract" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  "slots__state" INTEGER NOT NULL CHECK("slots__state" IN (2)),
  "slots" INTEGER REFERENCES "r_consequence_contract_slots"(__row_id),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind" IN ('action_consequences')),
  CHECK(("slots__state"=2 AND "slots" IS NOT NULL) OR ("slots__state" IN (0,1) AND "slots" IS NULL))
) STRICT;

CREATE TABLE "r_consequence_contract_slots" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_consequence_contract_slots_items" (owner INTEGER NOT NULL REFERENCES "r_consequence_contract_slots"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_effect_slot"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_effect_slot" (
  __row_id INTEGER PRIMARY KEY,
  "slot__state" INTEGER NOT NULL CHECK("slot__state" IN (2)),
  "slot" TEXT,
  "order__state" INTEGER NOT NULL CHECK("order__state" IN (2)),
  "order" TEXT,
  "presence__state" INTEGER NOT NULL CHECK("presence__state" IN (2)),
  "presence" TEXT,
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" INTEGER REFERENCES "r_effect_target"(__row_id),
  "condition__state" INTEGER NOT NULL CHECK("condition__state" IN (2)),
  "condition" INTEGER REFERENCES "r_effect_condition"(__row_id),
  "change__state" INTEGER NOT NULL CHECK("change__state" IN (2)),
  "change" INTEGER REFERENCES "r_effect_change"(__row_id),
  "lifetime__state" INTEGER NOT NULL CHECK("lifetime__state" IN (2)),
  "lifetime" INTEGER REFERENCES "r_effect_lifetime"(__row_id),
  CHECK(("slot__state"=2 AND "slot" IS NOT NULL) OR ("slot__state" IN (0,1) AND "slot" IS NULL)),
  CHECK(("order__state"=2 AND "order" IS NOT NULL) OR ("order__state" IN (0,1) AND "order" IS NULL)),
  CHECK(("presence__state"=2 AND "presence" IS NOT NULL) OR ("presence__state" IN (0,1) AND "presence" IS NULL)),
  CHECK("presence" IN ('required','optional')),
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("condition__state"=2 AND "condition" IS NOT NULL) OR ("condition__state" IN (0,1) AND "condition" IS NULL)),
  CHECK(("change__state"=2 AND "change" IS NOT NULL) OR ("change__state" IN (0,1) AND "change" IS NULL)),
  CHECK(("lifetime__state"=2 AND "lifetime" IS NOT NULL) OR ("lifetime__state" IN (0,1) AND "lifetime" IS NULL))
) STRICT;

CREATE TABLE "r_effect_target" (
  __row_id INTEGER PRIMARY KEY,
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" INTEGER REFERENCES "r_record_ref"(__row_id),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL))
) STRICT;

CREATE TABLE "r_effect_condition" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_effect_condition_v0"(__row_id),
  v1 INTEGER REFERENCES "r_effect_condition_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_effect_condition_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='always')
) STRICT;

CREATE TABLE "r_effect_condition_v1" (
  __row_id INTEGER PRIMARY KEY,
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" INTEGER REFERENCES "r_record_ref"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='attribute_equals')
) STRICT;

CREATE TABLE "r_effect_change" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_effect_change_v0"(__row_id),
  v1 INTEGER REFERENCES "r_effect_change_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_effect_change_v0" (
  __row_id INTEGER PRIMARY KEY,
  "polarity__state" INTEGER NOT NULL CHECK("polarity__state" IN (2)),
  "polarity" TEXT,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("polarity__state"=2 AND "polarity" IS NOT NULL) OR ("polarity__state" IN (0,1) AND "polarity" IS NULL)),
  CHECK("polarity" IN ('support','refutation')),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='set')
) STRICT;

CREATE TABLE "r_effect_change_v1" (
  __row_id INTEGER PRIMARY KEY,
  "delta__state" INTEGER NOT NULL CHECK("delta__state" IN (2)),
  "delta" TEXT,
  "minimum__state" INTEGER NOT NULL CHECK("minimum__state" IN (2)),
  "minimum" TEXT,
  "maximum__state" INTEGER NOT NULL CHECK("maximum__state" IN (2)),
  "maximum" TEXT,
  "unit__state" INTEGER NOT NULL CHECK("unit__state" IN (1,2)),
  "unit" INTEGER REFERENCES "r_effect_change_v1_unit"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("delta__state"=2 AND "delta" IS NOT NULL) OR ("delta__state" IN (0,1) AND "delta" IS NULL)),
  CHECK(("minimum__state"=2 AND "minimum" IS NOT NULL) OR ("minimum__state" IN (0,1) AND "minimum" IS NULL)),
  CHECK(("maximum__state"=2 AND "maximum" IS NOT NULL) OR ("maximum__state" IN (0,1) AND "maximum" IS NULL)),
  CHECK(("unit__state"=2 AND "unit" IS NOT NULL) OR ("unit__state" IN (0,1) AND "unit" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='delta')
) STRICT;

CREATE TABLE "r_effect_change_v1_unit" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_effect_lifetime" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_effect_lifetime_v0"(__row_id),
  v1 INTEGER REFERENCES "r_effect_lifetime_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_effect_lifetime_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='until_changed')
) STRICT;

CREATE TABLE "r_effect_lifetime_v1" (
  __row_id INTEGER PRIMARY KEY,
  "count__state" INTEGER NOT NULL CHECK("count__state" IN (2)),
  "count" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("count__state"=2 AND "count" IS NOT NULL) OR ("count__state" IN (0,1) AND "count" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='ticks')
) STRICT;

CREATE TABLE "r_payload_v27" (
  __row_id INTEGER PRIMARY KEY,
  "acquisition__state" INTEGER NOT NULL CHECK("acquisition__state" IN (0,1,2)),
  "acquisition" INTEGER REFERENCES "r_payload_v27_acquisition"(__row_id),
  "holder__state" INTEGER NOT NULL CHECK("holder__state" IN (2)),
  "holder" INTEGER REFERENCES "r_record_ref"(__row_id),
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" INTEGER REFERENCES "r_record_ref"(__row_id),
  "attitude__state" INTEGER NOT NULL CHECK("attitude__state" IN (2)),
  "attitude" TEXT,
  "certainty__state" INTEGER NOT NULL CHECK("certainty__state" IN (0,1,2)),
  "certainty" INTEGER REFERENCES "r_payload_v27_certainty"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "basis__state" INTEGER NOT NULL CHECK("basis__state" IN (2)),
  "basis" INTEGER REFERENCES "r_evidence_basis"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("acquisition__state"=2 AND "acquisition" IS NOT NULL) OR ("acquisition__state" IN (0,1) AND "acquisition" IS NULL)),
  CHECK(("holder__state"=2 AND "holder" IS NOT NULL) OR ("holder__state" IN (0,1) AND "holder" IS NULL)),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("attitude__state"=2 AND "attitude" IS NOT NULL) OR ("attitude__state" IN (0,1) AND "attitude" IS NULL)),
  CHECK("attitude" IN ('believes','suspects','rejects','remembers','knows')),
  CHECK(("certainty__state"=2 AND "certainty" IS NOT NULL) OR ("certainty__state" IN (0,1) AND "certainty" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("basis__state"=2 AND "basis" IS NOT NULL) OR ("basis__state" IN (0,1) AND "basis" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='epistemic_attitude')
) STRICT;

CREATE TABLE "r_payload_v27_acquisition" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_knowledge_acquisition"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_knowledge_acquisition" (
  __row_id INTEGER PRIMARY KEY,
  "truthContext__state" INTEGER NOT NULL CHECK("truthContext__state" IN (2)),
  "truthContext" INTEGER REFERENCES "r_record_ref"(__row_id),
  "time__state" INTEGER NOT NULL CHECK("time__state" IN (2)),
  "time" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "world__state" INTEGER NOT NULL CHECK("world__state" IN (0,1,2)),
  "world" INTEGER REFERENCES "r_knowledge_acquisition_world"(__row_id),
  "basis__state" INTEGER NOT NULL CHECK("basis__state" IN (2)),
  "basis" INTEGER REFERENCES "r_knowledge_basis"(__row_id),
  CHECK(("truthContext__state"=2 AND "truthContext" IS NOT NULL) OR ("truthContext__state" IN (0,1) AND "truthContext" IS NULL)),
  CHECK(("time__state"=2 AND "time" IS NOT NULL) OR ("time__state" IN (0,1) AND "time" IS NULL)),
  CHECK(("world__state"=2 AND "world" IS NOT NULL) OR ("world__state" IN (0,1) AND "world" IS NULL)),
  CHECK(("basis__state"=2 AND "basis" IS NOT NULL) OR ("basis__state" IN (0,1) AND "basis" IS NULL))
) STRICT;

CREATE TABLE "r_knowledge_acquisition_world" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_knowledge_basis" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_knowledge_basis_v0"(__row_id),
  v1 INTEGER REFERENCES "r_knowledge_basis_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_knowledge_basis_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='author_established')
) STRICT;

CREATE TABLE "r_knowledge_basis_v1" (
  __row_id INTEGER PRIMARY KEY,
  "communication__state" INTEGER NOT NULL CHECK("communication__state" IN (2)),
  "communication" INTEGER REFERENCES "r_record_ref"(__row_id),
  "interpretation__state" INTEGER NOT NULL CHECK("interpretation__state" IN (0,1,2)),
  "interpretation" INTEGER REFERENCES "r_knowledge_basis_v1_interpretation"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("communication__state"=2 AND "communication" IS NOT NULL) OR ("communication__state" IN (0,1) AND "communication" IS NULL)),
  CHECK(("interpretation__state"=2 AND "interpretation" IS NOT NULL) OR ("interpretation__state" IN (0,1) AND "interpretation" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='communication_receipt')
) STRICT;

CREATE TABLE "r_knowledge_basis_v1_interpretation" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v27_certainty" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v28" (
  __row_id INTEGER PRIMARY KEY,
  "observer__state" INTEGER NOT NULL CHECK("observer__state" IN (2)),
  "observer" INTEGER REFERENCES "r_record_ref"(__row_id),
  "observed__state" INTEGER NOT NULL CHECK("observed__state" IN (2)),
  "observed" INTEGER REFERENCES "r_record_ref"(__row_id),
  "sensoryAccess__state" INTEGER NOT NULL CHECK("sensoryAccess__state" IN (2)),
  "sensoryAccess" INTEGER,
  "time__state" INTEGER NOT NULL CHECK("time__state" IN (2)),
  "time" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "interpretation__state" INTEGER NOT NULL CHECK("interpretation__state" IN (0,1,2)),
  "interpretation" INTEGER REFERENCES "r_payload_v28_interpretation"(__row_id),
  "basis__state" INTEGER NOT NULL CHECK("basis__state" IN (2)),
  "basis" INTEGER REFERENCES "r_evidence_basis"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("observer__state"=2 AND "observer" IS NOT NULL) OR ("observer__state" IN (0,1) AND "observer" IS NULL)),
  CHECK(("observed__state"=2 AND "observed" IS NOT NULL) OR ("observed__state" IN (0,1) AND "observed" IS NULL)),
  CHECK(("sensoryAccess__state"=2 AND "sensoryAccess" IS NOT NULL) OR ("sensoryAccess__state" IN (0,1) AND "sensoryAccess" IS NULL)),
  CHECK("sensoryAccess" IN (0,1)),
  CHECK(("time__state"=2 AND "time" IS NOT NULL) OR ("time__state" IN (0,1) AND "time" IS NULL)),
  CHECK(("interpretation__state"=2 AND "interpretation" IS NOT NULL) OR ("interpretation__state" IN (0,1) AND "interpretation" IS NULL)),
  CHECK(("basis__state"=2 AND "basis" IS NOT NULL) OR ("basis__state" IN (0,1) AND "basis" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='observation')
) STRICT;

CREATE TABLE "r_payload_v28_interpretation" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v29" (
  __row_id INTEGER PRIMARY KEY,
  "sender__state" INTEGER NOT NULL CHECK("sender__state" IN (2)),
  "sender" INTEGER REFERENCES "r_record_ref"(__row_id),
  "intendedRecipients__state" INTEGER NOT NULL CHECK("intendedRecipients__state" IN (2)),
  "intendedRecipients" INTEGER REFERENCES "r_payload_v29_intended_recipients"(__row_id),
  "actualRecipients__state" INTEGER NOT NULL CHECK("actualRecipients__state" IN (2)),
  "actualRecipients" INTEGER REFERENCES "r_payload_v29_actual_recipients"(__row_id),
  "content__state" INTEGER NOT NULL CHECK("content__state" IN (2)),
  "content" INTEGER REFERENCES "r_payload_v29_content"(__row_id),
  "channel__state" INTEGER NOT NULL CHECK("channel__state" IN (0,1,2)),
  "channel" INTEGER REFERENCES "r_payload_v29_channel"(__row_id),
  "sentAt__state" INTEGER NOT NULL CHECK("sentAt__state" IN (2)),
  "sentAt" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "receivedAt__state" INTEGER NOT NULL CHECK("receivedAt__state" IN (0,1,2)),
  "receivedAt" INTEGER REFERENCES "r_payload_v29_received_at"(__row_id),
  "distorted__state" INTEGER NOT NULL CHECK("distorted__state" IN (2)),
  "distorted" INTEGER,
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("sender__state"=2 AND "sender" IS NOT NULL) OR ("sender__state" IN (0,1) AND "sender" IS NULL)),
  CHECK(("intendedRecipients__state"=2 AND "intendedRecipients" IS NOT NULL) OR ("intendedRecipients__state" IN (0,1) AND "intendedRecipients" IS NULL)),
  CHECK(("actualRecipients__state"=2 AND "actualRecipients" IS NOT NULL) OR ("actualRecipients__state" IN (0,1) AND "actualRecipients" IS NULL)),
  CHECK(("content__state"=2 AND "content" IS NOT NULL) OR ("content__state" IN (0,1) AND "content" IS NULL)),
  CHECK(("channel__state"=2 AND "channel" IS NOT NULL) OR ("channel__state" IN (0,1) AND "channel" IS NULL)),
  CHECK(("sentAt__state"=2 AND "sentAt" IS NOT NULL) OR ("sentAt__state" IN (0,1) AND "sentAt" IS NULL)),
  CHECK(("receivedAt__state"=2 AND "receivedAt" IS NOT NULL) OR ("receivedAt__state" IN (0,1) AND "receivedAt" IS NULL)),
  CHECK(("distorted__state"=2 AND "distorted" IS NOT NULL) OR ("distorted__state" IN (0,1) AND "distorted" IS NULL)),
  CHECK("distorted" IN (0,1)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='communication')
) STRICT;

CREATE TABLE "r_payload_v29_intended_recipients" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v29_intended_recipients_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v29_intended_recipients"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v29_actual_recipients" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v29_actual_recipients_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v29_actual_recipients"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v29_content" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v29_content_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v29_content"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v29_channel" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v29_received_at" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_temporal_expression"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v30" (
  __row_id INTEGER PRIMARY KEY,
  "holder__state" INTEGER NOT NULL CHECK("holder__state" IN (2)),
  "holder" INTEGER REFERENCES "r_record_ref"(__row_id),
  "content__state" INTEGER NOT NULL CHECK("content__state" IN (2)),
  "content" INTEGER REFERENCES "r_record_ref"(__row_id),
  "alleged__state" INTEGER NOT NULL CHECK("alleged__state" IN (0,1,2)),
  "alleged" INTEGER REFERENCES "r_payload_v30_alleged"(__row_id),
  "accessibility__state" INTEGER NOT NULL CHECK("accessibility__state" IN (2)),
  "accessibility" TEXT,
  "altered__state" INTEGER NOT NULL CHECK("altered__state" IN (2)),
  "altered" INTEGER,
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("holder__state"=2 AND "holder" IS NOT NULL) OR ("holder__state" IN (0,1) AND "holder" IS NULL)),
  CHECK(("content__state"=2 AND "content" IS NOT NULL) OR ("content__state" IN (0,1) AND "content" IS NULL)),
  CHECK(("alleged__state"=2 AND "alleged" IS NOT NULL) OR ("alleged__state" IN (0,1) AND "alleged" IS NULL)),
  CHECK(("accessibility__state"=2 AND "accessibility" IS NOT NULL) OR ("accessibility__state" IN (0,1) AND "accessibility" IS NULL)),
  CHECK(("altered__state"=2 AND "altered" IS NOT NULL) OR ("altered__state" IN (0,1) AND "altered" IS NULL)),
  CHECK("altered" IN (0,1)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='memory')
) STRICT;

CREATE TABLE "r_payload_v30_alleged" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v31" (
  __row_id INTEGER PRIMARY KEY,
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_payload_v31_scope"(__row_id),
  "fictionalKnowers__state" INTEGER NOT NULL CHECK("fictionalKnowers__state" IN (2)),
  "fictionalKnowers" INTEGER REFERENCES "r_payload_v31_fictional_knowers"(__row_id),
  "readerDisclosed__state" INTEGER NOT NULL CHECK("readerDisclosed__state" IN (2)),
  "readerDisclosed" INTEGER,
  "concealment__state" INTEGER NOT NULL CHECK("concealment__state" IN (0,1,2)),
  "concealment" INTEGER REFERENCES "r_payload_v31_concealment"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("fictionalKnowers__state"=2 AND "fictionalKnowers" IS NOT NULL) OR ("fictionalKnowers__state" IN (0,1) AND "fictionalKnowers" IS NULL)),
  CHECK(("readerDisclosed__state"=2 AND "readerDisclosed" IS NOT NULL) OR ("readerDisclosed__state" IN (0,1) AND "readerDisclosed" IS NULL)),
  CHECK("readerDisclosed" IN (0,1)),
  CHECK(("concealment__state"=2 AND "concealment" IS NOT NULL) OR ("concealment__state" IN (0,1) AND "concealment" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='secret')
) STRICT;

CREATE TABLE "r_payload_v31_scope" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v31_scope_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v31_scope"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v31_fictional_knowers" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v31_fictional_knowers_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v31_fictional_knowers"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v31_concealment" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v32" (
  __row_id INTEGER PRIMARY KEY,
  "actor__state" INTEGER NOT NULL CHECK("actor__state" IN (2)),
  "actor" INTEGER REFERENCES "r_record_ref"(__row_id),
  "desired__state" INTEGER NOT NULL CHECK("desired__state" IN (0,1,2)),
  "desired" INTEGER REFERENCES "r_payload_v32_desired"(__row_id),
  "prerequisites__state" INTEGER NOT NULL CHECK("prerequisites__state" IN (2)),
  "prerequisites" INTEGER REFERENCES "r_payload_v32_prerequisites"(__row_id),
  "steps__state" INTEGER NOT NULL CHECK("steps__state" IN (2)),
  "steps" INTEGER REFERENCES "r_payload_v32_steps"(__row_id),
  "status__state" INTEGER NOT NULL CHECK("status__state" IN (2)),
  "status" TEXT,
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("actor__state"=2 AND "actor" IS NOT NULL) OR ("actor__state" IN (0,1) AND "actor" IS NULL)),
  CHECK(("desired__state"=2 AND "desired" IS NOT NULL) OR ("desired__state" IN (0,1) AND "desired" IS NULL)),
  CHECK(("prerequisites__state"=2 AND "prerequisites" IS NOT NULL) OR ("prerequisites__state" IN (0,1) AND "prerequisites" IS NULL)),
  CHECK(("steps__state"=2 AND "steps" IS NOT NULL) OR ("steps__state" IN (0,1) AND "steps" IS NULL)),
  CHECK(("status__state"=2 AND "status" IS NOT NULL) OR ("status__state" IN (0,1) AND "status" IS NULL)),
  CHECK("status" IN ('active','abandoned','achieved')),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='goal')
) STRICT;

CREATE TABLE "r_payload_v32_desired" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v32_prerequisites" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v32_prerequisites_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v32_prerequisites"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v32_steps" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v32_steps_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v32_steps"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v33" (
  __row_id INTEGER PRIMARY KEY,
  "parties__state" INTEGER NOT NULL CHECK("parties__state" IN (2)),
  "parties" INTEGER REFERENCES "r_payload_v33_parties"(__row_id),
  "obligated__state" INTEGER NOT NULL CHECK("obligated__state" IN (2)),
  "obligated" INTEGER REFERENCES "r_record_ref"(__row_id),
  "conditions__state" INTEGER NOT NULL CHECK("conditions__state" IN (2)),
  "conditions" INTEGER REFERENCES "r_payload_v33_conditions"(__row_id),
  "deadline__state" INTEGER NOT NULL CHECK("deadline__state" IN (0,1,2)),
  "deadline" INTEGER REFERENCES "r_payload_v33_deadline"(__row_id),
  "status__state" INTEGER NOT NULL CHECK("status__state" IN (2)),
  "status" TEXT,
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("parties__state"=2 AND "parties" IS NOT NULL) OR ("parties__state" IN (0,1) AND "parties" IS NULL)),
  CHECK(("obligated__state"=2 AND "obligated" IS NOT NULL) OR ("obligated__state" IN (0,1) AND "obligated" IS NULL)),
  CHECK(("conditions__state"=2 AND "conditions" IS NOT NULL) OR ("conditions__state" IN (0,1) AND "conditions" IS NULL)),
  CHECK(("deadline__state"=2 AND "deadline" IS NOT NULL) OR ("deadline__state" IN (0,1) AND "deadline" IS NULL)),
  CHECK(("status__state"=2 AND "status" IS NOT NULL) OR ("status__state" IN (0,1) AND "status" IS NULL)),
  CHECK("status" IN ('unfulfilled','fulfilled','breached','released')),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='commitment')
) STRICT;

CREATE TABLE "r_payload_v33_parties" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v33_parties_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v33_parties"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_commitment_party"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_commitment_party" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v33_conditions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v33_conditions_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v33_conditions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v33_deadline" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_temporal_expression"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v34" (
  __row_id INTEGER PRIMARY KEY,
  "label__state" INTEGER NOT NULL CHECK("label__state" IN (2)),
  "label" TEXT,
  "externalId__state" INTEGER NOT NULL CHECK("externalId__state" IN (0,1,2)),
  "externalId" INTEGER REFERENCES "r_payload_v34_external_id"(__row_id),
  "origin__state" INTEGER NOT NULL CHECK("origin__state" IN (2)),
  "origin" INTEGER REFERENCES "r_origin_metadata"(__row_id),
  "versions__state" INTEGER NOT NULL CHECK("versions__state" IN (2)),
  "versions" INTEGER REFERENCES "r_payload_v34_versions"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("label__state"=2 AND "label" IS NOT NULL) OR ("label__state" IN (0,1) AND "label" IS NULL)),
  CHECK(("externalId__state"=2 AND "externalId" IS NOT NULL) OR ("externalId__state" IN (0,1) AND "externalId" IS NULL)),
  CHECK(("origin__state"=2 AND "origin" IS NOT NULL) OR ("origin__state" IN (0,1) AND "origin" IS NULL)),
  CHECK(("versions__state"=2 AND "versions" IS NOT NULL) OR ("versions__state" IN (0,1) AND "versions" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='source')
) STRICT;

CREATE TABLE "r_payload_v34_external_id" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_origin_metadata" (
  __row_id INTEGER PRIMARY KEY,
  "externallyAssertedAuthor__state" INTEGER NOT NULL CHECK("externallyAssertedAuthor__state" IN (0,1,2)),
  "externallyAssertedAuthor" INTEGER REFERENCES "r_origin_metadata_externally_asserted_author"(__row_id),
  "originNote__state" INTEGER NOT NULL CHECK("originNote__state" IN (0,1,2)),
  "originNote" INTEGER REFERENCES "r_origin_metadata_origin_note"(__row_id),
  CHECK(("externallyAssertedAuthor__state"=2 AND "externallyAssertedAuthor" IS NOT NULL) OR ("externallyAssertedAuthor__state" IN (0,1) AND "externallyAssertedAuthor" IS NULL)),
  CHECK(("originNote__state"=2 AND "originNote" IS NOT NULL) OR ("originNote__state" IN (0,1) AND "originNote" IS NULL))
) STRICT;

CREATE TABLE "r_origin_metadata_externally_asserted_author" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_origin_metadata_origin_note" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v34_versions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v34_versions_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v34_versions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v35" (
  __row_id INTEGER PRIMARY KEY,
  "source__state" INTEGER NOT NULL CHECK("source__state" IN (2)),
  "source" INTEGER REFERENCES "r_record_ref"(__row_id),
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  "mediaType__state" INTEGER NOT NULL CHECK("mediaType__state" IN (2)),
  "mediaType" TEXT,
  "byteSize__state" INTEGER NOT NULL CHECK("byteSize__state" IN (2)),
  "byteSize" TEXT,
  "importActor__state" INTEGER NOT NULL CHECK("importActor__state" IN (2)),
  "importActor" TEXT,
  "importTime__state" INTEGER NOT NULL CHECK("importTime__state" IN (2)),
  "importTime" TEXT,
  "decoding__state" INTEGER NOT NULL CHECK("decoding__state" IN (2)),
  "decoding" INTEGER REFERENCES "r_decoding_descriptor"(__row_id),
  "origin__state" INTEGER NOT NULL CHECK("origin__state" IN (2)),
  "origin" INTEGER REFERENCES "r_origin_metadata"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("source__state"=2 AND "source" IS NOT NULL) OR ("source__state" IN (0,1) AND "source" IS NULL)),
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL)),
  CHECK(("mediaType__state"=2 AND "mediaType" IS NOT NULL) OR ("mediaType__state" IN (0,1) AND "mediaType" IS NULL)),
  CHECK(("byteSize__state"=2 AND "byteSize" IS NOT NULL) OR ("byteSize__state" IN (0,1) AND "byteSize" IS NULL)),
  CHECK(("importActor__state"=2 AND "importActor" IS NOT NULL) OR ("importActor__state" IN (0,1) AND "importActor" IS NULL)),
  CHECK(("importTime__state"=2 AND "importTime" IS NOT NULL) OR ("importTime__state" IN (0,1) AND "importTime" IS NULL)),
  CHECK(("decoding__state"=2 AND "decoding" IS NOT NULL) OR ("decoding__state" IN (0,1) AND "decoding" IS NULL)),
  CHECK(("origin__state"=2 AND "origin" IS NOT NULL) OR ("origin__state" IN (0,1) AND "origin" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='source_version')
) STRICT;

CREATE TABLE "r_decoding_descriptor" (
  __row_id INTEGER PRIMARY KEY,
  "encoding__state" INTEGER NOT NULL CHECK("encoding__state" IN (2)),
  "encoding" TEXT,
  "representation__state" INTEGER NOT NULL CHECK("representation__state" IN (2)),
  "representation" TEXT,
  "byteLength__state" INTEGER NOT NULL CHECK("byteLength__state" IN (2)),
  "byteLength" TEXT,
  CHECK(("encoding__state"=2 AND "encoding" IS NOT NULL) OR ("encoding__state" IN (0,1) AND "encoding" IS NULL)),
  CHECK(("representation__state"=2 AND "representation" IS NOT NULL) OR ("representation__state" IN (0,1) AND "representation" IS NULL)),
  CHECK(("byteLength__state"=2 AND "byteLength" IS NOT NULL) OR ("byteLength__state" IN (0,1) AND "byteLength" IS NULL))
) STRICT;

CREATE TABLE "r_payload_v36" (
  __row_id INTEGER PRIMARY KEY,
  "sourceVersion__state" INTEGER NOT NULL CHECK("sourceVersion__state" IN (2)),
  "sourceVersion" INTEGER REFERENCES "r_version_ref"(__row_id),
  "locator__state" INTEGER NOT NULL CHECK("locator__state" IN (2)),
  "locator" INTEGER REFERENCES "r_anchor_locator"(__row_id),
  "excerptDigest__state" INTEGER NOT NULL CHECK("excerptDigest__state" IN (2)),
  "excerptDigest" TEXT,
  "excerpt__state" INTEGER NOT NULL CHECK("excerpt__state" IN (2)),
  "excerpt" TEXT,
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (0,1,2)),
  "context" INTEGER REFERENCES "r_payload_v36_context"(__row_id),
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("sourceVersion__state"=2 AND "sourceVersion" IS NOT NULL) OR ("sourceVersion__state" IN (0,1) AND "sourceVersion" IS NULL)),
  CHECK(("locator__state"=2 AND "locator" IS NOT NULL) OR ("locator__state" IN (0,1) AND "locator" IS NULL)),
  CHECK(("excerptDigest__state"=2 AND "excerptDigest" IS NOT NULL) OR ("excerptDigest__state" IN (0,1) AND "excerptDigest" IS NULL)),
  CHECK(("excerpt__state"=2 AND "excerpt" IS NOT NULL) OR ("excerpt__state" IN (0,1) AND "excerpt" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='anchor')
) STRICT;

CREATE TABLE "r_anchor_locator" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_anchor_locator_v0"(__row_id),
  v1 INTEGER REFERENCES "r_anchor_locator_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_anchor_locator_v0" (
  __row_id INTEGER PRIMARY KEY,
  "start__state" INTEGER NOT NULL CHECK("start__state" IN (2)),
  "start" TEXT,
  "end__state" INTEGER NOT NULL CHECK("end__state" IN (2)),
  "end" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("start__state"=2 AND "start" IS NOT NULL) OR ("start__state" IN (0,1) AND "start" IS NULL)),
  CHECK(("end__state"=2 AND "end" IS NOT NULL) OR ("end__state" IN (0,1) AND "end" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='byte_range')
) STRICT;

CREATE TABLE "r_anchor_locator_v1" (
  __row_id INTEGER PRIMARY KEY,
  "path__state" INTEGER NOT NULL CHECK("path__state" IN (2)),
  "path" INTEGER REFERENCES "r_anchor_locator_v1_path"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("path__state"=2 AND "path" IS NOT NULL) OR ("path__state" IN (0,1) AND "path" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='structural_path')
) STRICT;

CREATE TABLE "r_anchor_locator_v1_path" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_anchor_locator_v1_path_items" (owner INTEGER NOT NULL REFERENCES "r_anchor_locator_v1_path"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_payload_v36_context" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_payload_v37" (
  __row_id INTEGER PRIMARY KEY,
  "fingerprints__state" INTEGER NOT NULL CHECK("fingerprints__state" IN (2)),
  "fingerprints" INTEGER REFERENCES "r_payload_v37_fingerprints"(__row_id),
  "mode__state" INTEGER NOT NULL CHECK("mode__state" IN (2)),
  "mode" INTEGER REFERENCES "r_issue_decision_mode"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" TEXT,
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "principal__state" INTEGER NOT NULL CHECK("principal__state" IN (2)),
  "principal" TEXT,
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("fingerprints__state"=2 AND "fingerprints" IS NOT NULL) OR ("fingerprints__state" IN (0,1) AND "fingerprints" IS NULL)),
  CHECK(("mode__state"=2 AND "mode" IS NOT NULL) OR ("mode__state" IN (0,1) AND "mode" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("principal__state"=2 AND "principal" IS NOT NULL) OR ("principal__state" IN (0,1) AND "principal" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind"='issue_decision')
) STRICT;

CREATE TABLE "r_payload_v37_fingerprints" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_payload_v37_fingerprints_items" (owner INTEGER NOT NULL REFERENCES "r_payload_v37_fingerprints"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_issue_decision_mode" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 2),
  v0 TEXT,
  v1 TEXT,
  v2 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL)
) STRICT;

CREATE TABLE "r_domain_operation" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 55),
  v0 INTEGER REFERENCES "r_domain_operation_v0"(__row_id),
  v1 INTEGER REFERENCES "r_domain_operation_v1"(__row_id),
  v2 INTEGER REFERENCES "r_domain_operation_v2"(__row_id),
  v3 INTEGER REFERENCES "r_domain_operation_v3"(__row_id),
  v4 INTEGER REFERENCES "r_domain_operation_v4"(__row_id),
  v5 INTEGER REFERENCES "r_domain_operation_v5"(__row_id),
  v6 INTEGER REFERENCES "r_domain_operation_v6"(__row_id),
  v7 INTEGER REFERENCES "r_domain_operation_v7"(__row_id),
  v8 INTEGER REFERENCES "r_domain_operation_v8"(__row_id),
  v9 INTEGER REFERENCES "r_domain_operation_v9"(__row_id),
  v10 INTEGER REFERENCES "r_domain_operation_v10"(__row_id),
  v11 INTEGER REFERENCES "r_domain_operation_v11"(__row_id),
  v12 INTEGER REFERENCES "r_domain_operation_v12"(__row_id),
  v13 INTEGER REFERENCES "r_domain_operation_v13"(__row_id),
  v14 INTEGER REFERENCES "r_domain_operation_v14"(__row_id),
  v15 INTEGER REFERENCES "r_domain_operation_v15"(__row_id),
  v16 INTEGER REFERENCES "r_domain_operation_v16"(__row_id),
  v17 INTEGER REFERENCES "r_domain_operation_v17"(__row_id),
  v18 INTEGER REFERENCES "r_domain_operation_v18"(__row_id),
  v19 INTEGER REFERENCES "r_domain_operation_v19"(__row_id),
  v20 INTEGER REFERENCES "r_domain_operation_v20"(__row_id),
  v21 INTEGER REFERENCES "r_domain_operation_v21"(__row_id),
  v22 INTEGER REFERENCES "r_domain_operation_v22"(__row_id),
  v23 INTEGER REFERENCES "r_domain_operation_v23"(__row_id),
  v24 INTEGER REFERENCES "r_domain_operation_v24"(__row_id),
  v25 INTEGER REFERENCES "r_domain_operation_v25"(__row_id),
  v26 INTEGER REFERENCES "r_domain_operation_v26"(__row_id),
  v27 INTEGER REFERENCES "r_domain_operation_v27"(__row_id),
  v28 INTEGER REFERENCES "r_domain_operation_v28"(__row_id),
  v29 INTEGER REFERENCES "r_domain_operation_v29"(__row_id),
  v30 INTEGER REFERENCES "r_domain_operation_v30"(__row_id),
  v31 INTEGER REFERENCES "r_domain_operation_v31"(__row_id),
  v32 INTEGER REFERENCES "r_domain_operation_v32"(__row_id),
  v33 INTEGER REFERENCES "r_domain_operation_v33"(__row_id),
  v34 INTEGER REFERENCES "r_domain_operation_v34"(__row_id),
  v35 INTEGER REFERENCES "r_domain_operation_v35"(__row_id),
  v36 INTEGER REFERENCES "r_domain_operation_v36"(__row_id),
  v37 INTEGER REFERENCES "r_domain_operation_v37"(__row_id),
  v38 INTEGER REFERENCES "r_domain_operation_v38"(__row_id),
  v39 INTEGER REFERENCES "r_domain_operation_v39"(__row_id),
  v40 INTEGER REFERENCES "r_domain_operation_v40"(__row_id),
  v41 INTEGER REFERENCES "r_domain_operation_v41"(__row_id),
  v42 INTEGER REFERENCES "r_domain_operation_v42"(__row_id),
  v43 INTEGER REFERENCES "r_domain_operation_v43"(__row_id),
  v44 INTEGER REFERENCES "r_domain_operation_v44"(__row_id),
  v45 INTEGER REFERENCES "r_domain_operation_v45"(__row_id),
  v46 INTEGER REFERENCES "r_domain_operation_v46"(__row_id),
  v47 INTEGER REFERENCES "r_domain_operation_v47"(__row_id),
  v48 INTEGER REFERENCES "r_domain_operation_v48"(__row_id),
  v49 INTEGER REFERENCES "r_domain_operation_v49"(__row_id),
  v50 INTEGER REFERENCES "r_domain_operation_v50"(__row_id),
  v51 INTEGER REFERENCES "r_domain_operation_v51"(__row_id),
  v52 INTEGER REFERENCES "r_domain_operation_v52"(__row_id),
  v53 INTEGER REFERENCES "r_domain_operation_v53"(__row_id),
  v54 INTEGER REFERENCES "r_domain_operation_v54"(__row_id),
  v55 INTEGER REFERENCES "r_domain_operation_v55"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL),
  CHECK(variant=5 OR v5 IS NULL),
  CHECK(variant!=5 OR v5 IS NOT NULL),
  CHECK(variant=6 OR v6 IS NULL),
  CHECK(variant!=6 OR v6 IS NOT NULL),
  CHECK(variant=7 OR v7 IS NULL),
  CHECK(variant!=7 OR v7 IS NOT NULL),
  CHECK(variant=8 OR v8 IS NULL),
  CHECK(variant!=8 OR v8 IS NOT NULL),
  CHECK(variant=9 OR v9 IS NULL),
  CHECK(variant!=9 OR v9 IS NOT NULL),
  CHECK(variant=10 OR v10 IS NULL),
  CHECK(variant!=10 OR v10 IS NOT NULL),
  CHECK(variant=11 OR v11 IS NULL),
  CHECK(variant!=11 OR v11 IS NOT NULL),
  CHECK(variant=12 OR v12 IS NULL),
  CHECK(variant!=12 OR v12 IS NOT NULL),
  CHECK(variant=13 OR v13 IS NULL),
  CHECK(variant!=13 OR v13 IS NOT NULL),
  CHECK(variant=14 OR v14 IS NULL),
  CHECK(variant!=14 OR v14 IS NOT NULL),
  CHECK(variant=15 OR v15 IS NULL),
  CHECK(variant!=15 OR v15 IS NOT NULL),
  CHECK(variant=16 OR v16 IS NULL),
  CHECK(variant!=16 OR v16 IS NOT NULL),
  CHECK(variant=17 OR v17 IS NULL),
  CHECK(variant!=17 OR v17 IS NOT NULL),
  CHECK(variant=18 OR v18 IS NULL),
  CHECK(variant!=18 OR v18 IS NOT NULL),
  CHECK(variant=19 OR v19 IS NULL),
  CHECK(variant!=19 OR v19 IS NOT NULL),
  CHECK(variant=20 OR v20 IS NULL),
  CHECK(variant!=20 OR v20 IS NOT NULL),
  CHECK(variant=21 OR v21 IS NULL),
  CHECK(variant!=21 OR v21 IS NOT NULL),
  CHECK(variant=22 OR v22 IS NULL),
  CHECK(variant!=22 OR v22 IS NOT NULL),
  CHECK(variant=23 OR v23 IS NULL),
  CHECK(variant!=23 OR v23 IS NOT NULL),
  CHECK(variant=24 OR v24 IS NULL),
  CHECK(variant!=24 OR v24 IS NOT NULL),
  CHECK(variant=25 OR v25 IS NULL),
  CHECK(variant!=25 OR v25 IS NOT NULL),
  CHECK(variant=26 OR v26 IS NULL),
  CHECK(variant!=26 OR v26 IS NOT NULL),
  CHECK(variant=27 OR v27 IS NULL),
  CHECK(variant!=27 OR v27 IS NOT NULL),
  CHECK(variant=28 OR v28 IS NULL),
  CHECK(variant!=28 OR v28 IS NOT NULL),
  CHECK(variant=29 OR v29 IS NULL),
  CHECK(variant!=29 OR v29 IS NOT NULL),
  CHECK(variant=30 OR v30 IS NULL),
  CHECK(variant!=30 OR v30 IS NOT NULL),
  CHECK(variant=31 OR v31 IS NULL),
  CHECK(variant!=31 OR v31 IS NOT NULL),
  CHECK(variant=32 OR v32 IS NULL),
  CHECK(variant!=32 OR v32 IS NOT NULL),
  CHECK(variant=33 OR v33 IS NULL),
  CHECK(variant!=33 OR v33 IS NOT NULL),
  CHECK(variant=34 OR v34 IS NULL),
  CHECK(variant!=34 OR v34 IS NOT NULL),
  CHECK(variant=35 OR v35 IS NULL),
  CHECK(variant!=35 OR v35 IS NOT NULL),
  CHECK(variant=36 OR v36 IS NULL),
  CHECK(variant!=36 OR v36 IS NOT NULL),
  CHECK(variant=37 OR v37 IS NULL),
  CHECK(variant!=37 OR v37 IS NOT NULL),
  CHECK(variant=38 OR v38 IS NULL),
  CHECK(variant!=38 OR v38 IS NOT NULL),
  CHECK(variant=39 OR v39 IS NULL),
  CHECK(variant!=39 OR v39 IS NOT NULL),
  CHECK(variant=40 OR v40 IS NULL),
  CHECK(variant!=40 OR v40 IS NOT NULL),
  CHECK(variant=41 OR v41 IS NULL),
  CHECK(variant!=41 OR v41 IS NOT NULL),
  CHECK(variant=42 OR v42 IS NULL),
  CHECK(variant!=42 OR v42 IS NOT NULL),
  CHECK(variant=43 OR v43 IS NULL),
  CHECK(variant!=43 OR v43 IS NOT NULL),
  CHECK(variant=44 OR v44 IS NULL),
  CHECK(variant!=44 OR v44 IS NOT NULL),
  CHECK(variant=45 OR v45 IS NULL),
  CHECK(variant!=45 OR v45 IS NOT NULL),
  CHECK(variant=46 OR v46 IS NULL),
  CHECK(variant!=46 OR v46 IS NOT NULL),
  CHECK(variant=47 OR v47 IS NULL),
  CHECK(variant!=47 OR v47 IS NOT NULL),
  CHECK(variant=48 OR v48 IS NULL),
  CHECK(variant!=48 OR v48 IS NOT NULL),
  CHECK(variant=49 OR v49 IS NULL),
  CHECK(variant!=49 OR v49 IS NOT NULL),
  CHECK(variant=50 OR v50 IS NULL),
  CHECK(variant!=50 OR v50 IS NOT NULL),
  CHECK(variant=51 OR v51 IS NULL),
  CHECK(variant!=51 OR v51 IS NOT NULL),
  CHECK(variant=52 OR v52 IS NULL),
  CHECK(variant!=52 OR v52 IS NOT NULL),
  CHECK(variant=53 OR v53 IS NULL),
  CHECK(variant!=53 OR v53 IS NOT NULL),
  CHECK(variant=54 OR v54 IS NULL),
  CHECK(variant!=54 OR v54 IS NOT NULL),
  CHECK(variant=55 OR v55 IS NULL),
  CHECK(variant!=55 OR v55 IS NOT NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v0" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_appearance"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='create_appearance')
) STRICT;

CREATE TABLE "r_appearance" (
  __row_id INTEGER PRIMARY KEY,
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" INTEGER REFERENCES "r_appearance_target"(__row_id),
  "label__state" INTEGER NOT NULL CHECK("label__state" IN (2)),
  "label" TEXT,
  "physical_description__state" INTEGER NOT NULL CHECK("physical_description__state" IN (2)),
  "physical_description" TEXT,
  "atmosphere__state" INTEGER NOT NULL CHECK("atmosphere__state" IN (2)),
  "atmosphere" TEXT,
  "images__state" INTEGER NOT NULL CHECK("images__state" IN (2)),
  "images" INTEGER REFERENCES "r_appearance_images"(__row_id),
  "links__state" INTEGER NOT NULL CHECK("links__state" IN (2)),
  "links" INTEGER REFERENCES "r_appearance_links"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("label__state"=2 AND "label" IS NOT NULL) OR ("label__state" IN (0,1) AND "label" IS NULL)),
  CHECK(("physical_description__state"=2 AND "physical_description" IS NOT NULL) OR ("physical_description__state" IN (0,1) AND "physical_description" IS NULL)),
  CHECK(("atmosphere__state"=2 AND "atmosphere" IS NOT NULL) OR ("atmosphere__state" IN (0,1) AND "atmosphere" IS NULL)),
  CHECK(("images__state"=2 AND "images" IS NOT NULL) OR ("images__state" IN (0,1) AND "images" IS NULL)),
  CHECK(("links__state"=2 AND "links" IS NOT NULL) OR ("links__state" IN (0,1) AND "links" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL))
) STRICT;

CREATE TABLE "r_appearance_images" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_appearance_images_items" (owner INTEGER NOT NULL REFERENCES "r_appearance_images"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_appearance_image"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_appearance_links" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_appearance_links_items" (owner INTEGER NOT NULL REFERENCES "r_appearance_links"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_appearance_link"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v1" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "replacement__state" INTEGER NOT NULL CHECK("replacement__state" IN (2)),
  "replacement" INTEGER REFERENCES "r_appearance"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("replacement__state"=2 AND "replacement" IS NOT NULL) OR ("replacement__state" IN (0,1) AND "replacement" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='revise_appearance')
) STRICT;

CREATE TABLE "r_domain_operation_v2" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_image_asset"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='add_image_asset')
) STRICT;

CREATE TABLE "r_image_asset" (
  __row_id INTEGER PRIMARY KEY,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  "media_type__state" INTEGER NOT NULL CHECK("media_type__state" IN (2)),
  "media_type" TEXT,
  "byte_size__state" INTEGER NOT NULL CHECK("byte_size__state" IN (2)),
  "byte_size" TEXT,
  "width__state" INTEGER NOT NULL CHECK("width__state" IN (2)),
  "width" TEXT,
  "height__state" INTEGER NOT NULL CHECK("height__state" IN (2)),
  "height" TEXT,
  "original_name__state" INTEGER NOT NULL CHECK("original_name__state" IN (2)),
  "original_name" TEXT,
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL)),
  CHECK(("media_type__state"=2 AND "media_type" IS NOT NULL) OR ("media_type__state" IN (0,1) AND "media_type" IS NULL)),
  CHECK(("byte_size__state"=2 AND "byte_size" IS NOT NULL) OR ("byte_size__state" IN (0,1) AND "byte_size" IS NULL)),
  CHECK(("width__state"=2 AND "width" IS NOT NULL) OR ("width__state" IN (0,1) AND "width" IS NULL)),
  CHECK(("height__state"=2 AND "height" IS NOT NULL) OR ("height__state" IN (0,1) AND "height" IS NULL)),
  CHECK(("original_name__state"=2 AND "original_name" IS NOT NULL) OR ("original_name__state" IN (0,1) AND "original_name" IS NULL))
) STRICT;

CREATE TABLE "r_domain_operation_v3" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" TEXT,
  "mode__state" INTEGER NOT NULL CHECK("mode__state" IN (2)),
  "mode" TEXT,
  "reason__state" INTEGER NOT NULL CHECK("reason__state" IN (2)),
  "reason" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("mode__state"=2 AND "mode" IS NOT NULL) OR ("mode__state" IN (0,1) AND "mode" IS NULL)),
  CHECK("mode" IN ('elapsed','time_travel')),
  CHECK(("reason__state"=2 AND "reason" IS NOT NULL) OR ("reason__state" IN (0,1) AND "reason" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='set_story_time')
) STRICT;

CREATE TABLE "r_domain_operation_v4" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_entity"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='create_entity')
) STRICT;

CREATE TABLE "r_entity" (
  __row_id INTEGER PRIMARY KEY,
  "names__state" INTEGER NOT NULL CHECK("names__state" IN (2)),
  "names" INTEGER REFERENCES "r_entity_names"(__row_id),
  "classification__state" INTEGER NOT NULL CHECK("classification__state" IN (0,1,2)),
  "classification" INTEGER REFERENCES "r_entity_classification"(__row_id),
  "classificationResolution__state" INTEGER NOT NULL CHECK("classificationResolution__state" IN (2)),
  "classificationResolution" TEXT,
  "worldAssociations__state" INTEGER NOT NULL CHECK("worldAssociations__state" IN (2)),
  "worldAssociations" INTEGER REFERENCES "r_entity_world_associations"(__row_id),
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_entity_labels"(__row_id),
  "metadata__state" INTEGER NOT NULL CHECK("metadata__state" IN (2)),
  "metadata" INTEGER REFERENCES "r_entity_metadata"(__row_id),
  CHECK(("names__state"=2 AND "names" IS NOT NULL) OR ("names__state" IN (0,1) AND "names" IS NULL)),
  CHECK(("classification__state"=2 AND "classification" IS NOT NULL) OR ("classification__state" IN (0,1) AND "classification" IS NULL)),
  CHECK(("classificationResolution__state"=2 AND "classificationResolution" IS NOT NULL) OR ("classificationResolution__state" IN (0,1) AND "classificationResolution" IS NULL)),
  CHECK("classificationResolution" IN ('unclassified','resolved','ambiguous')),
  CHECK(("worldAssociations__state"=2 AND "worldAssociations" IS NOT NULL) OR ("worldAssociations__state" IN (0,1) AND "worldAssociations" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("metadata__state"=2 AND "metadata" IS NOT NULL) OR ("metadata__state" IN (0,1) AND "metadata" IS NULL))
) STRICT;

CREATE TABLE "r_entity_names" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_entity_names_items" (owner INTEGER NOT NULL REFERENCES "r_entity_names"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_contextual_name"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_entity_classification" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_entity_world_associations" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_entity_world_associations_items" (owner INTEGER NOT NULL REFERENCES "r_entity_world_associations"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_world_association"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_entity_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_entity_labels_items" (owner INTEGER NOT NULL REFERENCES "r_entity_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_entity_metadata" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_entity_metadata_items" (owner INTEGER NOT NULL REFERENCES "r_entity_metadata"(__row_id), name TEXT NOT NULL, item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_domain_operation_v5" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" INTEGER REFERENCES "r_contextual_name"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='add_name')
) STRICT;

CREATE TABLE "r_domain_operation_v6" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "entity_type__state" INTEGER NOT NULL CHECK("entity_type__state" IN (2)),
  "entity_type" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("entity_type__state"=2 AND "entity_type" IS NOT NULL) OR ("entity_type__state" IN (0,1) AND "entity_type" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='add_type_membership')
) STRICT;

CREATE TABLE "r_domain_operation_v7" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_world"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='create_world')
) STRICT;

CREATE TABLE "r_world" (
  __row_id INTEGER PRIMARY KEY,
  "selector__state" INTEGER NOT NULL CHECK("selector__state" IN (2)),
  "selector" TEXT,
  "aliases__state" INTEGER NOT NULL CHECK("aliases__state" IN (0,2)),
  "aliases" INTEGER REFERENCES "r_world_aliases"(__row_id),
  "settingType__state" INTEGER NOT NULL CHECK("settingType__state" IN (0,1,2)),
  "settingType" INTEGER REFERENCES "r_world_setting_type"(__row_id),
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (0,2)),
  "labels" INTEGER REFERENCES "r_world_labels"(__row_id),
  "metadata__state" INTEGER NOT NULL CHECK("metadata__state" IN (0,2)),
  "metadata" INTEGER REFERENCES "r_world_metadata"(__row_id),
  CHECK(("selector__state"=2 AND "selector" IS NOT NULL) OR ("selector__state" IN (0,1) AND "selector" IS NULL)),
  CHECK(("aliases__state"=2 AND "aliases" IS NOT NULL) OR ("aliases__state" IN (0,1) AND "aliases" IS NULL)),
  CHECK(("settingType__state"=2 AND "settingType" IS NOT NULL) OR ("settingType__state" IN (0,1) AND "settingType" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("metadata__state"=2 AND "metadata" IS NOT NULL) OR ("metadata__state" IN (0,1) AND "metadata" IS NULL))
) STRICT;

CREATE TABLE "r_world_aliases" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_world_aliases_items" (owner INTEGER NOT NULL REFERENCES "r_world_aliases"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_world_setting_type" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_world_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_world_labels_items" (owner INTEGER NOT NULL REFERENCES "r_world_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_world_metadata" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_world_metadata_items" (owner INTEGER NOT NULL REFERENCES "r_world_metadata"(__row_id), name TEXT NOT NULL, item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_domain_operation_v8" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "new_selector__state" INTEGER NOT NULL CHECK("new_selector__state" IN (2)),
  "new_selector" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("new_selector__state"=2 AND "new_selector" IS NOT NULL) OR ("new_selector__state" IN (0,1) AND "new_selector" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='rename_world_selector')
) STRICT;

CREATE TABLE "r_domain_operation_v9" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "alias__state" INTEGER NOT NULL CHECK("alias__state" IN (2)),
  "alias" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("alias__state"=2 AND "alias" IS NOT NULL) OR ("alias__state" IN (0,1) AND "alias" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='add_world_alias')
) STRICT;

CREATE TABLE "r_domain_operation_v10" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_work"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='create_work')
) STRICT;

CREATE TABLE "r_work" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" INTEGER REFERENCES "r_work_kind"(__row_id),
  "title__state" INTEGER NOT NULL CHECK("title__state" IN (2)),
  "title" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_work_labels"(__row_id),
  "sourceRefs__state" INTEGER NOT NULL CHECK("sourceRefs__state" IN (2)),
  "sourceRefs" INTEGER REFERENCES "r_work_source_refs"(__row_id),
  "versions__state" INTEGER NOT NULL CHECK("versions__state" IN (2)),
  "versions" INTEGER REFERENCES "r_work_versions"(__row_id),
  "worldAssociations__state" INTEGER NOT NULL CHECK("worldAssociations__state" IN (2)),
  "worldAssociations" INTEGER REFERENCES "r_work_world_associations"(__row_id),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK(("title__state"=2 AND "title" IS NOT NULL) OR ("title__state" IN (0,1) AND "title" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("sourceRefs__state"=2 AND "sourceRefs" IS NOT NULL) OR ("sourceRefs__state" IN (0,1) AND "sourceRefs" IS NULL)),
  CHECK(("versions__state"=2 AND "versions" IS NOT NULL) OR ("versions__state" IN (0,1) AND "versions" IS NULL)),
  CHECK(("worldAssociations__state"=2 AND "worldAssociations" IS NOT NULL) OR ("worldAssociations__state" IN (0,1) AND "worldAssociations" IS NULL))
) STRICT;

CREATE TABLE "r_work_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_work_labels_items" (owner INTEGER NOT NULL REFERENCES "r_work_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_work_source_refs" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_work_source_refs_items" (owner INTEGER NOT NULL REFERENCES "r_work_source_refs"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_work_versions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_work_versions_items" (owner INTEGER NOT NULL REFERENCES "r_work_versions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_work_world_associations" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_work_world_associations_items" (owner INTEGER NOT NULL REFERENCES "r_work_world_associations"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_world_association"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v11" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_saga"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='create_saga')
) STRICT;

CREATE TABLE "r_saga" (
  __row_id INTEGER PRIMARY KEY,
  "title__state" INTEGER NOT NULL CHECK("title__state" IN (2)),
  "title" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_saga_labels"(__row_id),
  "memberships__state" INTEGER NOT NULL CHECK("memberships__state" IN (2)),
  "memberships" INTEGER REFERENCES "r_saga_memberships"(__row_id),
  CHECK(("title__state"=2 AND "title" IS NOT NULL) OR ("title__state" IN (0,1) AND "title" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("memberships__state"=2 AND "memberships" IS NOT NULL) OR ("memberships__state" IN (0,1) AND "memberships" IS NULL))
) STRICT;

CREATE TABLE "r_saga_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_saga_labels_items" (owner INTEGER NOT NULL REFERENCES "r_saga_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_saga_memberships" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_saga_memberships_items" (owner INTEGER NOT NULL REFERENCES "r_saga_memberships"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_saga_membership"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v12" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "binding__state" INTEGER NOT NULL CHECK("binding__state" IN (2)),
  "binding" INTEGER REFERENCES "r_work_binding"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("binding__state"=2 AND "binding" IS NOT NULL) OR ("binding__state" IN (0,1) AND "binding" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='set_work_binding')
) STRICT;

CREATE TABLE "r_domain_operation_v13" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "association__state" INTEGER NOT NULL CHECK("association__state" IN (2)),
  "association" INTEGER REFERENCES "r_world_association"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("association__state"=2 AND "association" IS NOT NULL) OR ("association__state" IN (0,1) AND "association" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='associate_work_world')
) STRICT;

CREATE TABLE "r_domain_operation_v14" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "membership__state" INTEGER NOT NULL CHECK("membership__state" IN (2)),
  "membership" INTEGER REFERENCES "r_saga_membership"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("membership__state"=2 AND "membership" IS NOT NULL) OR ("membership__state" IN (0,1) AND "membership" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='set_saga_membership')
) STRICT;

CREATE TABLE "r_domain_operation_v15" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" INTEGER REFERENCES "r_proposition"(__row_id),
  "assertion__state" INTEGER NOT NULL CHECK("assertion__state" IN (2)),
  "assertion" INTEGER REFERENCES "r_assertion"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("assertion__state"=2 AND "assertion" IS NOT NULL) OR ("assertion__state" IN (0,1) AND "assertion" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='assert_proposition')
) STRICT;

CREATE TABLE "r_proposition" (
  __row_id INTEGER PRIMARY KEY,
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" INTEGER REFERENCES "r_record_ref"(__row_id),
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_record_ref"(__row_id),
  "roles__state" INTEGER NOT NULL CHECK("roles__state" IN (0,2)),
  "roles" INTEGER REFERENCES "r_proposition_roles"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (0,1,2)),
  "value" INTEGER REFERENCES "r_proposition_value"(__row_id),
  "quantification__state" INTEGER NOT NULL CHECK("quantification__state" IN (2)),
  "quantification" INTEGER REFERENCES "r_quantification"(__row_id),
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (2)),
  "context" INTEGER REFERENCES "r_record_ref"(__row_id),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("roles__state"=2 AND "roles" IS NOT NULL) OR ("roles__state" IN (0,1) AND "roles" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("quantification__state"=2 AND "quantification" IS NOT NULL) OR ("quantification__state" IN (0,1) AND "quantification" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL))
) STRICT;

CREATE TABLE "r_proposition_roles" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_proposition_roles_items" (owner INTEGER NOT NULL REFERENCES "r_proposition_roles"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_proposition_role"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_proposition_value" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_value"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_assertion" (
  __row_id INTEGER PRIMARY KEY,
  "attributeMode__state" INTEGER NOT NULL CHECK("attributeMode__state" IN (2)),
  "attributeMode" TEXT,
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" INTEGER REFERENCES "r_record_ref"(__row_id),
  "polarity__state" INTEGER NOT NULL CHECK("polarity__state" IN (2)),
  "polarity" TEXT,
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "persistence__state" INTEGER NOT NULL CHECK("persistence__state" IN (2)),
  "persistence" INTEGER REFERENCES "r_persistence_semantics"(__row_id),
  "precision__state" INTEGER NOT NULL CHECK("precision__state" IN (2)),
  "precision" TEXT,
  "alternatives__state" INTEGER NOT NULL CHECK("alternatives__state" IN (0,2)),
  "alternatives" INTEGER REFERENCES "r_assertion_alternatives"(__row_id),
  "basis__state" INTEGER NOT NULL CHECK("basis__state" IN (2)),
  "basis" INTEGER REFERENCES "r_evidence_basis"(__row_id),
  "establishedBy__state" INTEGER NOT NULL CHECK("establishedBy__state" IN (0,1,2)),
  "establishedBy" INTEGER REFERENCES "r_assertion_established_by"(__row_id),
  CHECK(("attributeMode__state"=2 AND "attributeMode" IS NOT NULL) OR ("attributeMode__state" IN (0,1) AND "attributeMode" IS NULL)),
  CHECK("attributeMode" IN ('instance','shared','initial_value')),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("polarity__state"=2 AND "polarity" IS NOT NULL) OR ("polarity__state" IN (0,1) AND "polarity" IS NULL)),
  CHECK("polarity" IN ('support','refutation')),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("persistence__state"=2 AND "persistence" IS NOT NULL) OR ("persistence__state" IN (0,1) AND "persistence" IS NULL)),
  CHECK(("precision__state"=2 AND "precision" IS NOT NULL) OR ("precision__state" IN (0,1) AND "precision" IS NULL)),
  CHECK("precision" IN ('exact','approximate','range','one_of','unresolved')),
  CHECK(("alternatives__state"=2 AND "alternatives" IS NOT NULL) OR ("alternatives__state" IN (0,1) AND "alternatives" IS NULL)),
  CHECK(("basis__state"=2 AND "basis" IS NOT NULL) OR ("basis__state" IN (0,1) AND "basis" IS NULL)),
  CHECK(("establishedBy__state"=2 AND "establishedBy" IS NOT NULL) OR ("establishedBy__state" IN (0,1) AND "establishedBy" IS NULL))
) STRICT;

CREATE TABLE "r_assertion_alternatives" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_assertion_alternatives_items" (owner INTEGER NOT NULL REFERENCES "r_assertion_alternatives"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_assertion_established_by" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_event_effect_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v16" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" INTEGER REFERENCES "r_proposition"(__row_id),
  "assertion__state" INTEGER NOT NULL CHECK("assertion__state" IN (2)),
  "assertion" INTEGER REFERENCES "r_assertion"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("assertion__state"=2 AND "assertion" IS NOT NULL) OR ("assertion__state" IN (0,1) AND "assertion" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_relation')
) STRICT;

CREATE TABLE "r_domain_operation_v17" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "at__state" INTEGER NOT NULL CHECK("at__state" IN (2)),
  "at" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "basis__state" INTEGER NOT NULL CHECK("basis__state" IN (2)),
  "basis" INTEGER REFERENCES "r_evidence_basis"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("at__state"=2 AND "at" IS NOT NULL) OR ("at__state" IN (0,1) AND "at" IS NULL)),
  CHECK(("basis__state"=2 AND "basis" IS NOT NULL) OR ("basis__state" IN (0,1) AND "basis" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='end_assertion_at')
) STRICT;

CREATE TABLE "r_domain_operation_v18" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "replacement__state" INTEGER NOT NULL CHECK("replacement__state" IN (2)),
  "replacement" INTEGER REFERENCES "r_assertion"(__row_id),
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("replacement__state"=2 AND "replacement" IS NOT NULL) OR ("replacement__state" IN (0,1) AND "replacement" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='supersede_assertion')
) STRICT;

CREATE TABLE "r_domain_operation_v19" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='retract_assertion')
) STRICT;

CREATE TABLE "r_domain_operation_v20" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_proposition"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_proposition')
) STRICT;

CREATE TABLE "r_domain_operation_v21" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_item_power"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_item_power')
) STRICT;

CREATE TABLE "r_item_power" (
  __row_id INTEGER PRIMARY KEY,
  "item__state" INTEGER NOT NULL CHECK("item__state" IN (2)),
  "item" INTEGER REFERENCES "r_record_ref"(__row_id),
  "holderPredicate__state" INTEGER NOT NULL CHECK("holderPredicate__state" IN (2)),
  "holderPredicate" INTEGER REFERENCES "r_record_ref"(__row_id),
  "powerPredicate__state" INTEGER NOT NULL CHECK("powerPredicate__state" IN (2)),
  "powerPredicate" INTEGER REFERENCES "r_record_ref"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  CHECK(("item__state"=2 AND "item" IS NOT NULL) OR ("item__state" IN (0,1) AND "item" IS NULL)),
  CHECK(("holderPredicate__state"=2 AND "holderPredicate" IS NOT NULL) OR ("holderPredicate__state" IN (0,1) AND "holderPredicate" IS NULL)),
  CHECK(("powerPredicate__state"=2 AND "powerPredicate" IS NOT NULL) OR ("powerPredicate__state" IN (0,1) AND "powerPredicate" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL))
) STRICT;

CREATE TABLE "r_domain_operation_v22" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_action_definition"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_action')
) STRICT;

CREATE TABLE "r_action_definition" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_action_definition_labels"(__row_id),
  "requirements__state" INTEGER NOT NULL CHECK("requirements__state" IN (2)),
  "requirements" INTEGER REFERENCES "r_action_definition_requirements"(__row_id),
  "consequenceContract__state" INTEGER NOT NULL CHECK("consequenceContract__state" IN (0,2)),
  "consequenceContract" INTEGER REFERENCES "r_consequence_contract"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("requirements__state"=2 AND "requirements" IS NOT NULL) OR ("requirements__state" IN (0,1) AND "requirements" IS NULL)),
  CHECK(("consequenceContract__state"=2 AND "consequenceContract" IS NOT NULL) OR ("consequenceContract__state" IN (0,1) AND "consequenceContract" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL))
) STRICT;

CREATE TABLE "r_action_definition_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_action_definition_labels_items" (owner INTEGER NOT NULL REFERENCES "r_action_definition_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_action_definition_requirements" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_action_definition_requirements_items" (owner INTEGER NOT NULL REFERENCES "r_action_definition_requirements"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_attribute_requirement"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v23" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_event"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_event')
) STRICT;

CREATE TABLE "r_event" (
  __row_id INTEGER PRIMARY KEY,
  "occurrence__state" INTEGER NOT NULL CHECK("occurrence__state" IN (2)),
  "occurrence" INTEGER REFERENCES "r_occurrence_mode"(__row_id),
  "action__state" INTEGER NOT NULL CHECK("action__state" IN (0,1,2)),
  "action" INTEGER REFERENCES "r_event_action"(__row_id),
  "worlds__state" INTEGER NOT NULL CHECK("worlds__state" IN (0,2)),
  "worlds" INTEGER REFERENCES "r_event_worlds"(__row_id),
  "region__state" INTEGER NOT NULL CHECK("region__state" IN (0,1,2)),
  "region" INTEGER REFERENCES "r_event_region"(__row_id),
  "time__state" INTEGER NOT NULL CHECK("time__state" IN (2)),
  "time" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "sequence__state" INTEGER NOT NULL CHECK("sequence__state" IN (0,1,2)),
  "sequence" INTEGER REFERENCES "r_event_sequence"(__row_id),
  "occurrenceId__state" INTEGER NOT NULL CHECK("occurrenceId__state" IN (0,1,2)),
  "occurrenceId" INTEGER REFERENCES "r_event_occurrence_id"(__row_id),
  "participants__state" INTEGER NOT NULL CHECK("participants__state" IN (2)),
  "participants" INTEGER REFERENCES "r_event_participants"(__row_id),
  "preconditions__state" INTEGER NOT NULL CHECK("preconditions__state" IN (0,2)),
  "preconditions" INTEGER REFERENCES "r_event_preconditions"(__row_id),
  "effects__state" INTEGER NOT NULL CHECK("effects__state" IN (0,2)),
  "effects" INTEGER REFERENCES "r_event_effects"(__row_id),
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_event_labels"(__row_id),
  "expansionVersion__state" INTEGER NOT NULL CHECK("expansionVersion__state" IN (0,1,2)),
  "expansionVersion" INTEGER REFERENCES "r_event_expansion_version"(__row_id),
  CHECK(("occurrence__state"=2 AND "occurrence" IS NOT NULL) OR ("occurrence__state" IN (0,1) AND "occurrence" IS NULL)),
  CHECK(("action__state"=2 AND "action" IS NOT NULL) OR ("action__state" IN (0,1) AND "action" IS NULL)),
  CHECK(("worlds__state"=2 AND "worlds" IS NOT NULL) OR ("worlds__state" IN (0,1) AND "worlds" IS NULL)),
  CHECK(("region__state"=2 AND "region" IS NOT NULL) OR ("region__state" IN (0,1) AND "region" IS NULL)),
  CHECK(("time__state"=2 AND "time" IS NOT NULL) OR ("time__state" IN (0,1) AND "time" IS NULL)),
  CHECK(("sequence__state"=2 AND "sequence" IS NOT NULL) OR ("sequence__state" IN (0,1) AND "sequence" IS NULL)),
  CHECK(("occurrenceId__state"=2 AND "occurrenceId" IS NOT NULL) OR ("occurrenceId__state" IN (0,1) AND "occurrenceId" IS NULL)),
  CHECK(("participants__state"=2 AND "participants" IS NOT NULL) OR ("participants__state" IN (0,1) AND "participants" IS NULL)),
  CHECK(("preconditions__state"=2 AND "preconditions" IS NOT NULL) OR ("preconditions__state" IN (0,1) AND "preconditions" IS NULL)),
  CHECK(("effects__state"=2 AND "effects" IS NOT NULL) OR ("effects__state" IN (0,1) AND "effects" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("expansionVersion__state"=2 AND "expansionVersion" IS NOT NULL) OR ("expansionVersion__state" IN (0,1) AND "expansionVersion" IS NULL))
) STRICT;

CREATE TABLE "r_event_action" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_event_worlds" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_event_worlds_items" (owner INTEGER NOT NULL REFERENCES "r_event_worlds"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_event_region" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_event_sequence" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_event_occurrence_id" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_event_participants" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_event_participants_items" (owner INTEGER NOT NULL REFERENCES "r_event_participants"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_event_participant"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_event_preconditions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_event_preconditions_items" (owner INTEGER NOT NULL REFERENCES "r_event_preconditions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_event_effects" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_event_effects_items" (owner INTEGER NOT NULL REFERENCES "r_event_effects"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_entity_effect"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_event_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_event_labels_items" (owner INTEGER NOT NULL REFERENCES "r_event_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_event_expansion_version" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v24" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "replacement__state" INTEGER NOT NULL CHECK("replacement__state" IN (2)),
  "replacement" INTEGER REFERENCES "r_event"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("replacement__state"=2 AND "replacement" IS NOT NULL) OR ("replacement__state" IN (0,1) AND "replacement" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='revise_event')
) STRICT;

CREATE TABLE "r_domain_operation_v25" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_epistemic_attitude"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='add_belief')
) STRICT;

CREATE TABLE "r_epistemic_attitude" (
  __row_id INTEGER PRIMARY KEY,
  "acquisition__state" INTEGER NOT NULL CHECK("acquisition__state" IN (0,1,2)),
  "acquisition" INTEGER REFERENCES "r_epistemic_attitude_acquisition"(__row_id),
  "holder__state" INTEGER NOT NULL CHECK("holder__state" IN (2)),
  "holder" INTEGER REFERENCES "r_record_ref"(__row_id),
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" INTEGER REFERENCES "r_record_ref"(__row_id),
  "attitude__state" INTEGER NOT NULL CHECK("attitude__state" IN (2)),
  "attitude" TEXT,
  "certainty__state" INTEGER NOT NULL CHECK("certainty__state" IN (0,1,2)),
  "certainty" INTEGER REFERENCES "r_epistemic_attitude_certainty"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "basis__state" INTEGER NOT NULL CHECK("basis__state" IN (2)),
  "basis" INTEGER REFERENCES "r_evidence_basis"(__row_id),
  CHECK(("acquisition__state"=2 AND "acquisition" IS NOT NULL) OR ("acquisition__state" IN (0,1) AND "acquisition" IS NULL)),
  CHECK(("holder__state"=2 AND "holder" IS NOT NULL) OR ("holder__state" IN (0,1) AND "holder" IS NULL)),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("attitude__state"=2 AND "attitude" IS NOT NULL) OR ("attitude__state" IN (0,1) AND "attitude" IS NULL)),
  CHECK("attitude" IN ('believes','suspects','rejects','remembers','knows')),
  CHECK(("certainty__state"=2 AND "certainty" IS NOT NULL) OR ("certainty__state" IN (0,1) AND "certainty" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("basis__state"=2 AND "basis" IS NOT NULL) OR ("basis__state" IN (0,1) AND "basis" IS NULL))
) STRICT;

CREATE TABLE "r_epistemic_attitude_acquisition" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_knowledge_acquisition"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_epistemic_attitude_certainty" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v26" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_observation"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_observation')
) STRICT;

CREATE TABLE "r_observation" (
  __row_id INTEGER PRIMARY KEY,
  "observer__state" INTEGER NOT NULL CHECK("observer__state" IN (2)),
  "observer" INTEGER REFERENCES "r_record_ref"(__row_id),
  "observed__state" INTEGER NOT NULL CHECK("observed__state" IN (2)),
  "observed" INTEGER REFERENCES "r_record_ref"(__row_id),
  "sensoryAccess__state" INTEGER NOT NULL CHECK("sensoryAccess__state" IN (2)),
  "sensoryAccess" INTEGER,
  "time__state" INTEGER NOT NULL CHECK("time__state" IN (2)),
  "time" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "interpretation__state" INTEGER NOT NULL CHECK("interpretation__state" IN (0,1,2)),
  "interpretation" INTEGER REFERENCES "r_observation_interpretation"(__row_id),
  "basis__state" INTEGER NOT NULL CHECK("basis__state" IN (2)),
  "basis" INTEGER REFERENCES "r_evidence_basis"(__row_id),
  CHECK(("observer__state"=2 AND "observer" IS NOT NULL) OR ("observer__state" IN (0,1) AND "observer" IS NULL)),
  CHECK(("observed__state"=2 AND "observed" IS NOT NULL) OR ("observed__state" IN (0,1) AND "observed" IS NULL)),
  CHECK(("sensoryAccess__state"=2 AND "sensoryAccess" IS NOT NULL) OR ("sensoryAccess__state" IN (0,1) AND "sensoryAccess" IS NULL)),
  CHECK("sensoryAccess" IN (0,1)),
  CHECK(("time__state"=2 AND "time" IS NOT NULL) OR ("time__state" IN (0,1) AND "time" IS NULL)),
  CHECK(("interpretation__state"=2 AND "interpretation" IS NOT NULL) OR ("interpretation__state" IN (0,1) AND "interpretation" IS NULL)),
  CHECK(("basis__state"=2 AND "basis" IS NOT NULL) OR ("basis__state" IN (0,1) AND "basis" IS NULL))
) STRICT;

CREATE TABLE "r_observation_interpretation" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v27" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_communication"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_communication')
) STRICT;

CREATE TABLE "r_communication" (
  __row_id INTEGER PRIMARY KEY,
  "sender__state" INTEGER NOT NULL CHECK("sender__state" IN (2)),
  "sender" INTEGER REFERENCES "r_record_ref"(__row_id),
  "intendedRecipients__state" INTEGER NOT NULL CHECK("intendedRecipients__state" IN (2)),
  "intendedRecipients" INTEGER REFERENCES "r_communication_intended_recipients"(__row_id),
  "actualRecipients__state" INTEGER NOT NULL CHECK("actualRecipients__state" IN (2)),
  "actualRecipients" INTEGER REFERENCES "r_communication_actual_recipients"(__row_id),
  "content__state" INTEGER NOT NULL CHECK("content__state" IN (2)),
  "content" INTEGER REFERENCES "r_communication_content"(__row_id),
  "channel__state" INTEGER NOT NULL CHECK("channel__state" IN (0,1,2)),
  "channel" INTEGER REFERENCES "r_communication_channel"(__row_id),
  "sentAt__state" INTEGER NOT NULL CHECK("sentAt__state" IN (2)),
  "sentAt" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "receivedAt__state" INTEGER NOT NULL CHECK("receivedAt__state" IN (0,1,2)),
  "receivedAt" INTEGER REFERENCES "r_communication_received_at"(__row_id),
  "distorted__state" INTEGER NOT NULL CHECK("distorted__state" IN (2)),
  "distorted" INTEGER,
  CHECK(("sender__state"=2 AND "sender" IS NOT NULL) OR ("sender__state" IN (0,1) AND "sender" IS NULL)),
  CHECK(("intendedRecipients__state"=2 AND "intendedRecipients" IS NOT NULL) OR ("intendedRecipients__state" IN (0,1) AND "intendedRecipients" IS NULL)),
  CHECK(("actualRecipients__state"=2 AND "actualRecipients" IS NOT NULL) OR ("actualRecipients__state" IN (0,1) AND "actualRecipients" IS NULL)),
  CHECK(("content__state"=2 AND "content" IS NOT NULL) OR ("content__state" IN (0,1) AND "content" IS NULL)),
  CHECK(("channel__state"=2 AND "channel" IS NOT NULL) OR ("channel__state" IN (0,1) AND "channel" IS NULL)),
  CHECK(("sentAt__state"=2 AND "sentAt" IS NOT NULL) OR ("sentAt__state" IN (0,1) AND "sentAt" IS NULL)),
  CHECK(("receivedAt__state"=2 AND "receivedAt" IS NOT NULL) OR ("receivedAt__state" IN (0,1) AND "receivedAt" IS NULL)),
  CHECK(("distorted__state"=2 AND "distorted" IS NOT NULL) OR ("distorted__state" IN (0,1) AND "distorted" IS NULL)),
  CHECK("distorted" IN (0,1))
) STRICT;

CREATE TABLE "r_communication_intended_recipients" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_communication_intended_recipients_items" (owner INTEGER NOT NULL REFERENCES "r_communication_intended_recipients"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_communication_actual_recipients" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_communication_actual_recipients_items" (owner INTEGER NOT NULL REFERENCES "r_communication_actual_recipients"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_communication_content" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_communication_content_items" (owner INTEGER NOT NULL REFERENCES "r_communication_content"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_communication_channel" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_communication_received_at" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_temporal_expression"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v28" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_memory"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_memory')
) STRICT;

CREATE TABLE "r_memory" (
  __row_id INTEGER PRIMARY KEY,
  "holder__state" INTEGER NOT NULL CHECK("holder__state" IN (2)),
  "holder" INTEGER REFERENCES "r_record_ref"(__row_id),
  "content__state" INTEGER NOT NULL CHECK("content__state" IN (2)),
  "content" INTEGER REFERENCES "r_record_ref"(__row_id),
  "alleged__state" INTEGER NOT NULL CHECK("alleged__state" IN (0,1,2)),
  "alleged" INTEGER REFERENCES "r_memory_alleged"(__row_id),
  "accessibility__state" INTEGER NOT NULL CHECK("accessibility__state" IN (2)),
  "accessibility" TEXT,
  "altered__state" INTEGER NOT NULL CHECK("altered__state" IN (2)),
  "altered" INTEGER,
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  CHECK(("holder__state"=2 AND "holder" IS NOT NULL) OR ("holder__state" IN (0,1) AND "holder" IS NULL)),
  CHECK(("content__state"=2 AND "content" IS NOT NULL) OR ("content__state" IN (0,1) AND "content" IS NULL)),
  CHECK(("alleged__state"=2 AND "alleged" IS NOT NULL) OR ("alleged__state" IN (0,1) AND "alleged" IS NULL)),
  CHECK(("accessibility__state"=2 AND "accessibility" IS NOT NULL) OR ("accessibility__state" IN (0,1) AND "accessibility" IS NULL)),
  CHECK(("altered__state"=2 AND "altered" IS NOT NULL) OR ("altered__state" IN (0,1) AND "altered" IS NULL)),
  CHECK("altered" IN (0,1)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL))
) STRICT;

CREATE TABLE "r_memory_alleged" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v29" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_goal"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_plan')
) STRICT;

CREATE TABLE "r_goal" (
  __row_id INTEGER PRIMARY KEY,
  "actor__state" INTEGER NOT NULL CHECK("actor__state" IN (2)),
  "actor" INTEGER REFERENCES "r_record_ref"(__row_id),
  "desired__state" INTEGER NOT NULL CHECK("desired__state" IN (0,1,2)),
  "desired" INTEGER REFERENCES "r_goal_desired"(__row_id),
  "prerequisites__state" INTEGER NOT NULL CHECK("prerequisites__state" IN (2)),
  "prerequisites" INTEGER REFERENCES "r_goal_prerequisites"(__row_id),
  "steps__state" INTEGER NOT NULL CHECK("steps__state" IN (2)),
  "steps" INTEGER REFERENCES "r_goal_steps"(__row_id),
  "status__state" INTEGER NOT NULL CHECK("status__state" IN (2)),
  "status" TEXT,
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  CHECK(("actor__state"=2 AND "actor" IS NOT NULL) OR ("actor__state" IN (0,1) AND "actor" IS NULL)),
  CHECK(("desired__state"=2 AND "desired" IS NOT NULL) OR ("desired__state" IN (0,1) AND "desired" IS NULL)),
  CHECK(("prerequisites__state"=2 AND "prerequisites" IS NOT NULL) OR ("prerequisites__state" IN (0,1) AND "prerequisites" IS NULL)),
  CHECK(("steps__state"=2 AND "steps" IS NOT NULL) OR ("steps__state" IN (0,1) AND "steps" IS NULL)),
  CHECK(("status__state"=2 AND "status" IS NOT NULL) OR ("status__state" IN (0,1) AND "status" IS NULL)),
  CHECK("status" IN ('active','abandoned','achieved')),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL))
) STRICT;

CREATE TABLE "r_goal_desired" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_goal_prerequisites" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_goal_prerequisites_items" (owner INTEGER NOT NULL REFERENCES "r_goal_prerequisites"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_goal_steps" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_goal_steps_items" (owner INTEGER NOT NULL REFERENCES "r_goal_steps"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v30" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_commitment"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_commitment')
) STRICT;

CREATE TABLE "r_commitment" (
  __row_id INTEGER PRIMARY KEY,
  "parties__state" INTEGER NOT NULL CHECK("parties__state" IN (2)),
  "parties" INTEGER REFERENCES "r_commitment_parties"(__row_id),
  "obligated__state" INTEGER NOT NULL CHECK("obligated__state" IN (2)),
  "obligated" INTEGER REFERENCES "r_record_ref"(__row_id),
  "conditions__state" INTEGER NOT NULL CHECK("conditions__state" IN (2)),
  "conditions" INTEGER REFERENCES "r_commitment_conditions"(__row_id),
  "deadline__state" INTEGER NOT NULL CHECK("deadline__state" IN (0,1,2)),
  "deadline" INTEGER REFERENCES "r_commitment_deadline"(__row_id),
  "status__state" INTEGER NOT NULL CHECK("status__state" IN (2)),
  "status" TEXT,
  CHECK(("parties__state"=2 AND "parties" IS NOT NULL) OR ("parties__state" IN (0,1) AND "parties" IS NULL)),
  CHECK(("obligated__state"=2 AND "obligated" IS NOT NULL) OR ("obligated__state" IN (0,1) AND "obligated" IS NULL)),
  CHECK(("conditions__state"=2 AND "conditions" IS NOT NULL) OR ("conditions__state" IN (0,1) AND "conditions" IS NULL)),
  CHECK(("deadline__state"=2 AND "deadline" IS NOT NULL) OR ("deadline__state" IN (0,1) AND "deadline" IS NULL)),
  CHECK(("status__state"=2 AND "status" IS NOT NULL) OR ("status__state" IN (0,1) AND "status" IS NULL)),
  CHECK("status" IN ('unfulfilled','fulfilled','breached','released'))
) STRICT;

CREATE TABLE "r_commitment_parties" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_commitment_parties_items" (owner INTEGER NOT NULL REFERENCES "r_commitment_parties"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_commitment_party"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_commitment_conditions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_commitment_conditions_items" (owner INTEGER NOT NULL REFERENCES "r_commitment_conditions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_commitment_deadline" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_temporal_expression"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v31" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_entity_type"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_type')
) STRICT;

CREATE TABLE "r_entity_type" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_entity_type_labels"(__row_id),
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "parent__state" INTEGER NOT NULL CHECK("parent__state" IN (1,2)),
  "parent" INTEGER REFERENCES "r_entity_type_parent"(__row_id),
  "parentResolution__state" INTEGER NOT NULL CHECK("parentResolution__state" IN (2)),
  "parentResolution" TEXT,
  "applicability__state" INTEGER NOT NULL CHECK("applicability__state" IN (2)),
  "applicability" INTEGER REFERENCES "r_applicability"(__row_id),
  "classificationExecutable__state" INTEGER NOT NULL CHECK("classificationExecutable__state" IN (2)),
  "classificationExecutable" INTEGER,
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("parent__state"=2 AND "parent" IS NOT NULL) OR ("parent__state" IN (0,1) AND "parent" IS NULL)),
  CHECK(("parentResolution__state"=2 AND "parentResolution" IS NOT NULL) OR ("parentResolution__state" IN (0,1) AND "parentResolution" IS NULL)),
  CHECK("parentResolution" IN ('root','resolved','ambiguous')),
  CHECK(("applicability__state"=2 AND "applicability" IS NOT NULL) OR ("applicability__state" IN (0,1) AND "applicability" IS NULL)),
  CHECK(("classificationExecutable__state"=2 AND "classificationExecutable" IS NOT NULL) OR ("classificationExecutable__state" IN (0,1) AND "classificationExecutable" IS NULL)),
  CHECK("classificationExecutable" IN (0,1))
) STRICT;

CREATE TABLE "r_entity_type_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_entity_type_labels_items" (owner INTEGER NOT NULL REFERENCES "r_entity_type_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_entity_type_parent" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v32" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_property_def"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_property')
) STRICT;

CREATE TABLE "r_property_def" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_property_def_labels"(__row_id),
  "subjectTypes__state" INTEGER NOT NULL CHECK("subjectTypes__state" IN (0,2)),
  "subjectTypes" INTEGER REFERENCES "r_property_def_subject_types"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value_shape"(__row_id),
  "multiplicity__state" INTEGER NOT NULL CHECK("multiplicity__state" IN (2)),
  "multiplicity" TEXT,
  "unitDimension__state" INTEGER NOT NULL CHECK("unitDimension__state" IN (0,1,2)),
  "unitDimension" INTEGER REFERENCES "r_property_def_unit_dimension"(__row_id),
  "persistence__state" INTEGER NOT NULL CHECK("persistence__state" IN (2)),
  "persistence" INTEGER REFERENCES "r_persistence_semantics"(__row_id),
  "exclusive__state" INTEGER NOT NULL CHECK("exclusive__state" IN (2)),
  "exclusive" INTEGER,
  "inverse__state" INTEGER NOT NULL CHECK("inverse__state" IN (0,1,2)),
  "inverse" INTEGER REFERENCES "r_property_def_inverse"(__row_id),
  "symmetric__state" INTEGER NOT NULL CHECK("symmetric__state" IN (2)),
  "symmetric" INTEGER,
  "transitive__state" INTEGER NOT NULL CHECK("transitive__state" IN (2)),
  "transitive" INTEGER,
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("subjectTypes__state"=2 AND "subjectTypes" IS NOT NULL) OR ("subjectTypes__state" IN (0,1) AND "subjectTypes" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("multiplicity__state"=2 AND "multiplicity" IS NOT NULL) OR ("multiplicity__state" IN (0,1) AND "multiplicity" IS NULL)),
  CHECK("multiplicity" IN ('single','multiple')),
  CHECK(("unitDimension__state"=2 AND "unitDimension" IS NOT NULL) OR ("unitDimension__state" IN (0,1) AND "unitDimension" IS NULL)),
  CHECK(("persistence__state"=2 AND "persistence" IS NOT NULL) OR ("persistence__state" IN (0,1) AND "persistence" IS NULL)),
  CHECK(("exclusive__state"=2 AND "exclusive" IS NOT NULL) OR ("exclusive__state" IN (0,1) AND "exclusive" IS NULL)),
  CHECK("exclusive" IN (0,1)),
  CHECK(("inverse__state"=2 AND "inverse" IS NOT NULL) OR ("inverse__state" IN (0,1) AND "inverse" IS NULL)),
  CHECK(("symmetric__state"=2 AND "symmetric" IS NOT NULL) OR ("symmetric__state" IN (0,1) AND "symmetric" IS NULL)),
  CHECK("symmetric" IN (0,1)),
  CHECK(("transitive__state"=2 AND "transitive" IS NOT NULL) OR ("transitive__state" IN (0,1) AND "transitive" IS NULL)),
  CHECK("transitive" IN (0,1))
) STRICT;

CREATE TABLE "r_property_def_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_property_def_labels_items" (owner INTEGER NOT NULL REFERENCES "r_property_def_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_property_def_subject_types" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_property_def_subject_types_items" (owner INTEGER NOT NULL REFERENCES "r_property_def_subject_types"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_property_def_unit_dimension" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_property_def_inverse" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v33" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_relation_def"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_relation')
) STRICT;

CREATE TABLE "r_relation_def" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_relation_def_labels"(__row_id),
  "roles__state" INTEGER NOT NULL CHECK("roles__state" IN (2)),
  "roles" INTEGER REFERENCES "r_relation_def_roles"(__row_id),
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("roles__state"=2 AND "roles" IS NOT NULL) OR ("roles__state" IN (0,1) AND "roles" IS NULL))
) STRICT;

CREATE TABLE "r_relation_def_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_relation_def_labels_items" (owner INTEGER NOT NULL REFERENCES "r_relation_def_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_relation_def_roles" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_relation_def_roles_items" (owner INTEGER NOT NULL REFERENCES "r_relation_def_roles"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_role_def"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v34" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_unit_def"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_unit')
) STRICT;

CREATE TABLE "r_unit_def" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "dimension__state" INTEGER NOT NULL CHECK("dimension__state" IN (2)),
  "dimension" TEXT,
  "symbol__state" INTEGER NOT NULL CHECK("symbol__state" IN (2)),
  "symbol" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_unit_def_labels"(__row_id),
  "scaleToBase__state" INTEGER NOT NULL CHECK("scaleToBase__state" IN (0,1,2)),
  "scaleToBase" INTEGER REFERENCES "r_unit_def_scale_to_base"(__row_id),
  "base__state" INTEGER NOT NULL CHECK("base__state" IN (0,1,2)),
  "base" INTEGER REFERENCES "r_unit_def_base"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("dimension__state"=2 AND "dimension" IS NOT NULL) OR ("dimension__state" IN (0,1) AND "dimension" IS NULL)),
  CHECK(("symbol__state"=2 AND "symbol" IS NOT NULL) OR ("symbol__state" IN (0,1) AND "symbol" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("scaleToBase__state"=2 AND "scaleToBase" IS NOT NULL) OR ("scaleToBase__state" IN (0,1) AND "scaleToBase" IS NULL)),
  CHECK(("base__state"=2 AND "base" IS NOT NULL) OR ("base__state" IN (0,1) AND "base" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL))
) STRICT;

CREATE TABLE "r_unit_def_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_unit_def_labels_items" (owner INTEGER NOT NULL REFERENCES "r_unit_def_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_unit_def_scale_to_base" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_value"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_unit_def_base" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v35" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_calendar_def"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_calendar')
) STRICT;

CREATE TABLE "r_calendar_def" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_calendar_def_labels"(__row_id),
  "epoch__state" INTEGER NOT NULL CHECK("epoch__state" IN (0,1,2)),
  "epoch" INTEGER REFERENCES "r_calendar_def_epoch"(__row_id),
  "unitStructure__state" INTEGER NOT NULL CHECK("unitStructure__state" IN (2)),
  "unitStructure" INTEGER REFERENCES "r_calendar_def_unit_structure"(__row_id),
  "conversions__state" INTEGER NOT NULL CHECK("conversions__state" IN (0,2)),
  "conversions" INTEGER REFERENCES "r_calendar_def_conversions"(__row_id),
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("epoch__state"=2 AND "epoch" IS NOT NULL) OR ("epoch__state" IN (0,1) AND "epoch" IS NULL)),
  CHECK(("unitStructure__state"=2 AND "unitStructure" IS NOT NULL) OR ("unitStructure__state" IN (0,1) AND "unitStructure" IS NULL)),
  CHECK(("conversions__state"=2 AND "conversions" IS NOT NULL) OR ("conversions__state" IN (0,1) AND "conversions" IS NULL))
) STRICT;

CREATE TABLE "r_calendar_def_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_calendar_def_labels_items" (owner INTEGER NOT NULL REFERENCES "r_calendar_def_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_calendar_def_epoch" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_calendar_def_unit_structure" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_calendar_def_unit_structure_items" (owner INTEGER NOT NULL REFERENCES "r_calendar_def_unit_structure"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_calendar_def_conversions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_calendar_def_conversions_items" (owner INTEGER NOT NULL REFERENCES "r_calendar_def_conversions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_calendar_conversion"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v36" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_value_def"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_value')
) STRICT;

CREATE TABLE "r_value_def" (
  __row_id INTEGER PRIMARY KEY,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_value_def_labels"(__row_id),
  "fields__state" INTEGER NOT NULL CHECK("fields__state" IN (2)),
  "fields" INTEGER REFERENCES "r_value_def_fields"(__row_id),
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("fields__state"=2 AND "fields" IS NOT NULL) OR ("fields__state" IN (0,1) AND "fields" IS NULL))
) STRICT;

CREATE TABLE "r_value_def_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_value_def_labels_items" (owner INTEGER NOT NULL REFERENCES "r_value_def_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_value_def_fields" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_value_def_fields_items" (owner INTEGER NOT NULL REFERENCES "r_value_def_fields"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_value_def_field"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v37" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_rule"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='define_rule')
) STRICT;

CREATE TABLE "r_rule" (
  __row_id INTEGER PRIMARY KEY,
  "knowledgePolicy__state" INTEGER NOT NULL CHECK("knowledgePolicy__state" IN (0,1,2)),
  "knowledgePolicy" INTEGER REFERENCES "r_rule_knowledge_policy"(__row_id),
  "channelChronology__state" INTEGER NOT NULL CHECK("channelChronology__state" IN (0,1,2)),
  "channelChronology" INTEGER REFERENCES "r_rule_channel_chronology"(__row_id),
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "labels__state" INTEGER NOT NULL CHECK("labels__state" IN (2)),
  "labels" INTEGER REFERENCES "r_rule_labels"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" INTEGER REFERENCES "r_rule_kind"(__row_id),
  "commitPolicy__state" INTEGER NOT NULL CHECK("commitPolicy__state" IN (2)),
  "commitPolicy" INTEGER REFERENCES "r_commit_policy"(__row_id),
  "applicability__state" INTEGER NOT NULL CHECK("applicability__state" IN (2)),
  "applicability" INTEGER REFERENCES "r_applicability"(__row_id),
  "subjectTypes__state" INTEGER NOT NULL CHECK("subjectTypes__state" IN (0,2)),
  "subjectTypes" INTEGER REFERENCES "r_rule_subject_types"(__row_id),
  "targetPredicates__state" INTEGER NOT NULL CHECK("targetPredicates__state" IN (2)),
  "targetPredicates" INTEGER REFERENCES "r_rule_target_predicates"(__row_id),
  "expression__state" INTEGER NOT NULL CHECK("expression__state" IN (2)),
  "expression" INTEGER REFERENCES "r_expr"(__row_id),
  "capabilities__state" INTEGER NOT NULL CHECK("capabilities__state" IN (2)),
  "capabilities" INTEGER REFERENCES "r_rule_capabilities"(__row_id),
  "executable__state" INTEGER NOT NULL CHECK("executable__state" IN (2)),
  "executable" INTEGER,
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  CHECK(("knowledgePolicy__state"=2 AND "knowledgePolicy" IS NOT NULL) OR ("knowledgePolicy__state" IN (0,1) AND "knowledgePolicy" IS NULL)),
  CHECK(("channelChronology__state"=2 AND "channelChronology" IS NOT NULL) OR ("channelChronology__state" IN (0,1) AND "channelChronology" IS NULL)),
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("labels__state"=2 AND "labels" IS NOT NULL) OR ("labels__state" IN (0,1) AND "labels" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK(("commitPolicy__state"=2 AND "commitPolicy" IS NOT NULL) OR ("commitPolicy__state" IN (0,1) AND "commitPolicy" IS NULL)),
  CHECK(("applicability__state"=2 AND "applicability" IS NOT NULL) OR ("applicability__state" IN (0,1) AND "applicability" IS NULL)),
  CHECK(("subjectTypes__state"=2 AND "subjectTypes" IS NOT NULL) OR ("subjectTypes__state" IN (0,1) AND "subjectTypes" IS NULL)),
  CHECK(("targetPredicates__state"=2 AND "targetPredicates" IS NOT NULL) OR ("targetPredicates__state" IN (0,1) AND "targetPredicates" IS NULL)),
  CHECK(("expression__state"=2 AND "expression" IS NOT NULL) OR ("expression__state" IN (0,1) AND "expression" IS NULL)),
  CHECK(("capabilities__state"=2 AND "capabilities" IS NOT NULL) OR ("capabilities__state" IN (0,1) AND "capabilities" IS NULL)),
  CHECK(("executable__state"=2 AND "executable" IS NOT NULL) OR ("executable__state" IN (0,1) AND "executable" IS NULL)),
  CHECK("executable" IN (0,1)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL))
) STRICT;

CREATE TABLE "r_rule_knowledge_policy" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_knowledge_policy"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_rule_channel_chronology" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_channel_chronology"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_rule_labels" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_rule_labels_items" (owner INTEGER NOT NULL REFERENCES "r_rule_labels"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_rule_subject_types" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_rule_subject_types_items" (owner INTEGER NOT NULL REFERENCES "r_rule_subject_types"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_rule_target_predicates" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_rule_target_predicates_items" (owner INTEGER NOT NULL REFERENCES "r_rule_target_predicates"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_rule_capabilities" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_rule_capabilities_items" (owner INTEGER NOT NULL REFERENCES "r_rule_capabilities"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v38" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_completeness_decl"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='set_completeness')
) STRICT;

CREATE TABLE "r_completeness_decl" (
  __row_id INTEGER PRIMARY KEY,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_record_ref"(__row_id),
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" TEXT,
  "members__state" INTEGER NOT NULL CHECK("members__state" IN (2)),
  "members" INTEGER REFERENCES "r_completeness_decl_members"(__row_id),
  "completeness__state" INTEGER NOT NULL CHECK("completeness__state" IN (2)),
  "completeness" INTEGER REFERENCES "r_completeness_kind"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("members__state"=2 AND "members" IS NOT NULL) OR ("members__state" IN (0,1) AND "members" IS NULL)),
  CHECK(("completeness__state"=2 AND "completeness" IS NOT NULL) OR ("completeness__state" IN (0,1) AND "completeness" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL))
) STRICT;

CREATE TABLE "r_completeness_decl_members" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_completeness_decl_members_items" (owner INTEGER NOT NULL REFERENCES "r_completeness_decl_members"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_record_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v39" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_creative_boundary"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='set_creative_boundary')
) STRICT;

CREATE TABLE "r_creative_boundary" (
  __row_id INTEGER PRIMARY KEY,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "area__state" INTEGER NOT NULL CHECK("area__state" IN (2)),
  "area" INTEGER REFERENCES "r_boundary_area"(__row_id),
  "mode__state" INTEGER NOT NULL CHECK("mode__state" IN (2)),
  "mode" INTEGER REFERENCES "r_boundary_mode"(__row_id),
  "constraints__state" INTEGER NOT NULL CHECK("constraints__state" IN (0,2)),
  "constraints" INTEGER REFERENCES "r_creative_boundary_constraints"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("area__state"=2 AND "area" IS NOT NULL) OR ("area__state" IN (0,1) AND "area" IS NULL)),
  CHECK(("mode__state"=2 AND "mode" IS NOT NULL) OR ("mode__state" IN (0,1) AND "mode" IS NULL)),
  CHECK(("constraints__state"=2 AND "constraints" IS NOT NULL) OR ("constraints__state" IN (0,1) AND "constraints" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL))
) STRICT;

CREATE TABLE "r_creative_boundary_constraints" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_creative_boundary_constraints_items" (owner INTEGER NOT NULL REFERENCES "r_creative_boundary_constraints"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_expr"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v40" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_exception"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='add_exception')
) STRICT;

CREATE TABLE "r_exception" (
  __row_id INTEGER PRIMARY KEY,
  "rule__state" INTEGER NOT NULL CHECK("rule__state" IN (2)),
  "rule" INTEGER REFERENCES "r_record_ref"(__row_id),
  "ruleVersion__state" INTEGER NOT NULL CHECK("ruleVersion__state" IN (0,1,2)),
  "ruleVersion" INTEGER REFERENCES "r_exception_rule_version"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "authorizingDecision__state" INTEGER NOT NULL CHECK("authorizingDecision__state" IN (2)),
  "authorizingDecision" INTEGER REFERENCES "r_record_ref"(__row_id),
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  CHECK(("rule__state"=2 AND "rule" IS NOT NULL) OR ("rule__state" IN (0,1) AND "rule" IS NULL)),
  CHECK(("ruleVersion__state"=2 AND "ruleVersion" IS NOT NULL) OR ("ruleVersion__state" IN (0,1) AND "ruleVersion" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("authorizingDecision__state"=2 AND "authorizingDecision" IS NOT NULL) OR ("authorizingDecision__state" IN (0,1) AND "authorizingDecision" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL))
) STRICT;

CREATE TABLE "r_exception_rule_version" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v41" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_anchor"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='add_source_anchor')
) STRICT;

CREATE TABLE "r_anchor" (
  __row_id INTEGER PRIMARY KEY,
  "sourceVersion__state" INTEGER NOT NULL CHECK("sourceVersion__state" IN (2)),
  "sourceVersion" INTEGER REFERENCES "r_version_ref"(__row_id),
  "locator__state" INTEGER NOT NULL CHECK("locator__state" IN (2)),
  "locator" INTEGER REFERENCES "r_anchor_locator"(__row_id),
  "excerptDigest__state" INTEGER NOT NULL CHECK("excerptDigest__state" IN (2)),
  "excerptDigest" TEXT,
  "excerpt__state" INTEGER NOT NULL CHECK("excerpt__state" IN (2)),
  "excerpt" TEXT,
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (0,1,2)),
  "context" INTEGER REFERENCES "r_anchor_context"(__row_id),
  CHECK(("sourceVersion__state"=2 AND "sourceVersion" IS NOT NULL) OR ("sourceVersion__state" IN (0,1) AND "sourceVersion" IS NULL)),
  CHECK(("locator__state"=2 AND "locator" IS NOT NULL) OR ("locator__state" IN (0,1) AND "locator" IS NULL)),
  CHECK(("excerptDigest__state"=2 AND "excerptDigest" IS NOT NULL) OR ("excerptDigest__state" IN (0,1) AND "excerptDigest" IS NULL)),
  CHECK(("excerpt__state"=2 AND "excerpt" IS NOT NULL) OR ("excerpt__state" IN (0,1) AND "excerpt" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL))
) STRICT;

CREATE TABLE "r_anchor_context" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v42" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" TEXT,
  "payload__state" INTEGER NOT NULL CHECK("payload__state" IN (2)),
  "payload" INTEGER REFERENCES "r_payload"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK("record" IN ('entity','appearance','image_asset','world','realm','work','work_version','scene_ref','passage_ref','saga','entity_type','property','relation','unit','calendar','value_definition','domain_pack','proposition','assertion','represented_context','completeness','boundary','rule','exception','event','item_power','action_definition','epistemic_attitude','observation','communication','memory','secret','goal','commitment','source','source_version','anchor','issue_decision')),
  CHECK(("payload__state"=2 AND "payload" IS NOT NULL) OR ("payload__state" IN (0,1) AND "payload" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_narrative_reference')
) STRICT;

CREATE TABLE "r_domain_operation_v43" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_issue_decision"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_issue_decision')
) STRICT;

CREATE TABLE "r_issue_decision" (
  __row_id INTEGER PRIMARY KEY,
  "fingerprints__state" INTEGER NOT NULL CHECK("fingerprints__state" IN (2)),
  "fingerprints" INTEGER REFERENCES "r_issue_decision_fingerprints"(__row_id),
  "mode__state" INTEGER NOT NULL CHECK("mode__state" IN (2)),
  "mode" INTEGER REFERENCES "r_issue_decision_mode"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" TEXT,
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "principal__state" INTEGER NOT NULL CHECK("principal__state" IN (2)),
  "principal" TEXT,
  CHECK(("fingerprints__state"=2 AND "fingerprints" IS NOT NULL) OR ("fingerprints__state" IN (0,1) AND "fingerprints" IS NULL)),
  CHECK(("mode__state"=2 AND "mode" IS NOT NULL) OR ("mode__state" IN (0,1) AND "mode" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("principal__state"=2 AND "principal" IS NOT NULL) OR ("principal__state" IN (0,1) AND "principal" IS NULL))
) STRICT;

CREATE TABLE "r_issue_decision_fingerprints" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_issue_decision_fingerprints_items" (owner INTEGER NOT NULL REFERENCES "r_issue_decision_fingerprints"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v44" (
  __row_id INTEGER PRIMARY KEY,
  "source__state" INTEGER NOT NULL CHECK("source__state" IN (2)),
  "source" INTEGER REFERENCES "r_record_version"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (0,1,2)),
  "expected_version" INTEGER REFERENCES "r_domain_operation_v44_expected_version"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("source__state"=2 AND "source" IS NOT NULL) OR ("source__state" IN (0,1) AND "source" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='adopt_record_version')
) STRICT;

CREATE TABLE "r_record_version" (
  __row_id INTEGER PRIMARY KEY,
  "record_version_id__state" INTEGER NOT NULL CHECK("record_version_id__state" IN (2)),
  "record_version_id" TEXT,
  "identity__state" INTEGER NOT NULL CHECK("identity__state" IN (2)),
  "identity" INTEGER REFERENCES "r_record_identity"(__row_id),
  "payload__state" INTEGER NOT NULL CHECK("payload__state" IN (2)),
  "payload" INTEGER REFERENCES "r_payload"(__row_id),
  "payload_digest__state" INTEGER NOT NULL CHECK("payload_digest__state" IN (2)),
  "payload_digest" TEXT,
  CHECK(("record_version_id__state"=2 AND "record_version_id" IS NOT NULL) OR ("record_version_id__state" IN (0,1) AND "record_version_id" IS NULL)),
  CHECK(("identity__state"=2 AND "identity" IS NOT NULL) OR ("identity__state" IN (0,1) AND "identity" IS NULL)),
  CHECK(("payload__state"=2 AND "payload" IS NOT NULL) OR ("payload__state" IN (0,1) AND "payload" IS NULL)),
  CHECK(("payload_digest__state"=2 AND "payload_digest" IS NOT NULL) OR ("payload_digest__state" IN (0,1) AND "payload_digest" IS NULL))
) STRICT;

CREATE TABLE "r_record_identity" (
  __row_id INTEGER PRIMARY KEY,
  "universe_id__state" INTEGER NOT NULL CHECK("universe_id__state" IN (2)),
  "universe_id" TEXT,
  "record_id__state" INTEGER NOT NULL CHECK("record_id__state" IN (2)),
  "record_id" TEXT,
  "record_kind__state" INTEGER NOT NULL CHECK("record_kind__state" IN (2)),
  "record_kind" TEXT,
  CHECK(("universe_id__state"=2 AND "universe_id" IS NOT NULL) OR ("universe_id__state" IN (0,1) AND "universe_id" IS NULL)),
  CHECK(("record_id__state"=2 AND "record_id" IS NOT NULL) OR ("record_id__state" IN (0,1) AND "record_id" IS NULL)),
  CHECK(("record_kind__state"=2 AND "record_kind" IS NOT NULL) OR ("record_kind__state" IN (0,1) AND "record_kind" IS NULL)),
  CHECK("record_kind" IN ('entity','appearance','image_asset','world','realm','work','work_version','scene_ref','passage_ref','saga','entity_type','property','relation','unit','calendar','value_definition','domain_pack','proposition','assertion','represented_context','completeness','boundary','rule','exception','event','item_power','action_definition','epistemic_attitude','observation','communication','memory','secret','goal','commitment','source','source_version','anchor','issue_decision'))
) STRICT;

CREATE TABLE "r_domain_operation_v44_expected_version" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v45" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='tombstone_record')
) STRICT;

CREATE TABLE "r_domain_operation_v46" (
  __row_id INTEGER PRIMARY KEY,
  "source__state" INTEGER NOT NULL CHECK("source__state" IN (2)),
  "source" INTEGER REFERENCES "r_record_ref"(__row_id),
  "source_version__state" INTEGER NOT NULL CHECK("source_version__state" IN (2)),
  "source_version" TEXT,
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" INTEGER REFERENCES "r_record_ref"(__row_id),
  "target_version__state" INTEGER NOT NULL CHECK("target_version__state" IN (2)),
  "target_version" TEXT,
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("source__state"=2 AND "source" IS NOT NULL) OR ("source__state" IN (0,1) AND "source" IS NULL)),
  CHECK(("source_version__state"=2 AND "source_version" IS NOT NULL) OR ("source_version__state" IN (0,1) AND "source_version" IS NULL)),
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("target_version__state"=2 AND "target_version" IS NOT NULL) OR ("target_version__state" IN (0,1) AND "target_version" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='merge_entities')
) STRICT;

CREATE TABLE "r_domain_operation_v47" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_domain_pack"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='install_pack')
) STRICT;

CREATE TABLE "r_domain_pack" (
  __row_id INTEGER PRIMARY KEY,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  "dependencies__state" INTEGER NOT NULL CHECK("dependencies__state" IN (2)),
  "dependencies" INTEGER REFERENCES "r_domain_pack_dependencies"(__row_id),
  "capabilities__state" INTEGER NOT NULL CHECK("capabilities__state" IN (2)),
  "capabilities" INTEGER REFERENCES "r_domain_pack_capabilities"(__row_id),
  "records__state" INTEGER NOT NULL CHECK("records__state" IN (2)),
  "records" INTEGER REFERENCES "r_domain_pack_records"(__row_id),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL)),
  CHECK(("dependencies__state"=2 AND "dependencies" IS NOT NULL) OR ("dependencies__state" IN (0,1) AND "dependencies" IS NULL)),
  CHECK(("capabilities__state"=2 AND "capabilities" IS NOT NULL) OR ("capabilities__state" IN (0,1) AND "capabilities" IS NULL)),
  CHECK(("records__state"=2 AND "records" IS NOT NULL) OR ("records__state" IN (0,1) AND "records" IS NULL))
) STRICT;

CREATE TABLE "r_domain_pack_dependencies" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_domain_pack_dependencies_items" (owner INTEGER NOT NULL REFERENCES "r_domain_pack_dependencies"(__row_id), name TEXT NOT NULL, item TEXT, PRIMARY KEY(owner,name)) STRICT;

CREATE TABLE "r_domain_pack_capabilities" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_domain_pack_capabilities_items" (owner INTEGER NOT NULL REFERENCES "r_domain_pack_capabilities"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_pack_records" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_domain_pack_records_items" (owner INTEGER NOT NULL REFERENCES "r_domain_pack_records"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v48" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "replacement__state" INTEGER NOT NULL CHECK("replacement__state" IN (2)),
  "replacement" INTEGER REFERENCES "r_payload"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("replacement__state"=2 AND "replacement" IS NOT NULL) OR ("replacement__state" IN (0,1) AND "replacement" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='revise_definition')
) STRICT;

CREATE TABLE "r_domain_operation_v49" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "replacement__state" INTEGER NOT NULL CHECK("replacement__state" IN (2)),
  "replacement" INTEGER REFERENCES "r_domain_pack"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("replacement__state"=2 AND "replacement" IS NOT NULL) OR ("replacement__state" IN (0,1) AND "replacement" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='upgrade_pack')
) STRICT;

CREATE TABLE "r_domain_operation_v50" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "parent__state" INTEGER NOT NULL CHECK("parent__state" IN (0,1,2)),
  "parent" INTEGER REFERENCES "r_domain_operation_v50_parent"(__row_id),
  "applicability__state" INTEGER NOT NULL CHECK("applicability__state" IN (2)),
  "applicability" INTEGER REFERENCES "r_applicability"(__row_id),
  "classification_executable__state" INTEGER NOT NULL CHECK("classification_executable__state" IN (2)),
  "classification_executable" INTEGER,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("parent__state"=2 AND "parent" IS NOT NULL) OR ("parent__state" IN (0,1) AND "parent" IS NULL)),
  CHECK(("applicability__state"=2 AND "applicability" IS NOT NULL) OR ("applicability__state" IN (0,1) AND "applicability" IS NULL)),
  CHECK(("classification_executable__state"=2 AND "classification_executable" IS NOT NULL) OR ("classification_executable__state" IN (0,1) AND "classification_executable" IS NULL)),
  CHECK("classification_executable" IN (0,1)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='introduce_definition')
) STRICT;

CREATE TABLE "r_domain_operation_v50_parent" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v51" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" INTEGER REFERENCES "r_contextual_name"(__row_id),
  "classification__state" INTEGER NOT NULL CHECK("classification__state" IN (0,1,2)),
  "classification" INTEGER REFERENCES "r_domain_operation_v51_classification"(__row_id),
  "world_associations__state" INTEGER NOT NULL CHECK("world_associations__state" IN (2)),
  "world_associations" INTEGER REFERENCES "r_domain_operation_v51_world_associations"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("classification__state"=2 AND "classification" IS NOT NULL) OR ("classification__state" IN (0,1) AND "classification" IS NULL)),
  CHECK(("world_associations__state"=2 AND "world_associations" IS NOT NULL) OR ("world_associations__state" IN (0,1) AND "world_associations" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='introduce_instance')
) STRICT;

CREATE TABLE "r_domain_operation_v51_classification" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_domain_operation_v51_world_associations" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_domain_operation_v51_world_associations_items" (owner INTEGER NOT NULL REFERENCES "r_domain_operation_v51_world_associations"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_world_association"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v52" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_record_ref"(__row_id),
  "namespace__state" INTEGER NOT NULL CHECK("namespace__state" IN (2)),
  "namespace" TEXT,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "value_shape__state" INTEGER NOT NULL CHECK("value_shape__state" IN (2)),
  "value_shape" INTEGER REFERENCES "r_value_shape"(__row_id),
  "subject_types__state" INTEGER NOT NULL CHECK("subject_types__state" IN (2)),
  "subject_types" INTEGER REFERENCES "r_domain_operation_v52_subject_types"(__row_id),
  "multiplicity__state" INTEGER NOT NULL CHECK("multiplicity__state" IN (2)),
  "multiplicity" TEXT,
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  "evidence__state" INTEGER NOT NULL CHECK("evidence__state" IN (2)),
  "evidence" INTEGER REFERENCES "r_attribute_evidence"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("namespace__state"=2 AND "namespace" IS NOT NULL) OR ("namespace__state" IN (0,1) AND "namespace" IS NULL)),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("value_shape__state"=2 AND "value_shape" IS NOT NULL) OR ("value_shape__state" IN (0,1) AND "value_shape" IS NULL)),
  CHECK(("subject_types__state"=2 AND "subject_types" IS NOT NULL) OR ("subject_types__state" IN (0,1) AND "subject_types" IS NULL)),
  CHECK(("multiplicity__state"=2 AND "multiplicity" IS NOT NULL) OR ("multiplicity__state" IN (0,1) AND "multiplicity" IS NULL)),
  CHECK("multiplicity" IN ('single','multiple')),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("evidence__state"=2 AND "evidence" IS NOT NULL) OR ("evidence__state" IN (0,1) AND "evidence" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='add_named_attribute')
) STRICT;

CREATE TABLE "r_domain_operation_v52_subject_types" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_domain_operation_v52_subject_types_items" (owner INTEGER NOT NULL REFERENCES "r_domain_operation_v52_subject_types"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_attribute_evidence" (
  __row_id INTEGER PRIMARY KEY,
  "attributeMode__state" INTEGER NOT NULL CHECK("attributeMode__state" IN (2)),
  "attributeMode" TEXT,
  "polarity__state" INTEGER NOT NULL CHECK("polarity__state" IN (2)),
  "polarity" TEXT,
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "persistence__state" INTEGER NOT NULL CHECK("persistence__state" IN (2)),
  "persistence" INTEGER REFERENCES "r_persistence_semantics"(__row_id),
  "precision__state" INTEGER NOT NULL CHECK("precision__state" IN (2)),
  "precision" TEXT,
  "alternatives__state" INTEGER NOT NULL CHECK("alternatives__state" IN (0,2)),
  "alternatives" INTEGER REFERENCES "r_attribute_evidence_alternatives"(__row_id),
  "basis__state" INTEGER NOT NULL CHECK("basis__state" IN (2)),
  "basis" INTEGER REFERENCES "r_evidence_basis"(__row_id),
  CHECK(("attributeMode__state"=2 AND "attributeMode" IS NOT NULL) OR ("attributeMode__state" IN (0,1) AND "attributeMode" IS NULL)),
  CHECK("attributeMode" IN ('instance','shared','initial_value')),
  CHECK(("polarity__state"=2 AND "polarity" IS NOT NULL) OR ("polarity__state" IN (0,1) AND "polarity" IS NULL)),
  CHECK("polarity" IN ('support','refutation')),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("persistence__state"=2 AND "persistence" IS NOT NULL) OR ("persistence__state" IN (0,1) AND "persistence" IS NULL)),
  CHECK(("precision__state"=2 AND "precision" IS NOT NULL) OR ("precision__state" IN (0,1) AND "precision" IS NULL)),
  CHECK("precision" IN ('exact','approximate','range','one_of','unresolved')),
  CHECK(("alternatives__state"=2 AND "alternatives" IS NOT NULL) OR ("alternatives__state" IN (0,1) AND "alternatives" IS NULL)),
  CHECK(("basis__state"=2 AND "basis" IS NOT NULL) OR ("basis__state" IN (0,1) AND "basis" IS NULL))
) STRICT;

CREATE TABLE "r_attribute_evidence_alternatives" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_attribute_evidence_alternatives_items" (owner INTEGER NOT NULL REFERENCES "r_attribute_evidence_alternatives"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_value"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_domain_operation_v53" (
  __row_id INTEGER PRIMARY KEY,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "instance__state" INTEGER NOT NULL CHECK("instance__state" IN (2)),
  "instance" INTEGER REFERENCES "r_record_ref"(__row_id),
  "start__state" INTEGER NOT NULL CHECK("start__state" IN (2)),
  "start" INTEGER REFERENCES "r_record_ref"(__row_id),
  "definition__state" INTEGER NOT NULL CHECK("definition__state" IN (2)),
  "definition" INTEGER REFERENCES "r_version_ref"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("instance__state"=2 AND "instance" IS NOT NULL) OR ("instance__state" IN (0,1) AND "instance" IS NULL)),
  CHECK(("start__state"=2 AND "start" IS NOT NULL) OR ("start__state" IN (0,1) AND "start" IS NULL)),
  CHECK(("definition__state"=2 AND "definition" IS NOT NULL) OR ("definition__state" IN (0,1) AND "definition" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='initialize_instance')
) STRICT;

CREATE TABLE "r_domain_operation_v54" (
  __row_id INTEGER PRIMARY KEY,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" INTEGER REFERENCES "r_record_ref"(__row_id),
  "expected_version__state" INTEGER NOT NULL CHECK("expected_version__state" IN (2)),
  "expected_version" TEXT,
  "entity_type__state" INTEGER NOT NULL CHECK("entity_type__state" IN (2)),
  "entity_type" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("expected_version__state"=2 AND "expected_version" IS NOT NULL) OR ("expected_version__state" IN (0,1) AND "expected_version" IS NULL)),
  CHECK(("entity_type__state"=2 AND "entity_type" IS NOT NULL) OR ("entity_type__state" IN (0,1) AND "entity_type" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='refine_classification')
) STRICT;

CREATE TABLE "r_domain_operation_v55" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  "client_ref__state" INTEGER NOT NULL CHECK("client_ref__state" IN (2)),
  "client_ref" TEXT,
  "instance__state" INTEGER NOT NULL CHECK("instance__state" IN (2)),
  "instance" INTEGER REFERENCES "r_record_ref"(__row_id),
  "start__state" INTEGER NOT NULL CHECK("start__state" IN (2)),
  "start" INTEGER REFERENCES "r_record_ref"(__row_id),
  "definition__state" INTEGER NOT NULL CHECK("definition__state" IN (2)),
  "definition" INTEGER REFERENCES "r_version_ref"(__row_id),
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" INTEGER REFERENCES "r_scope"(__row_id),
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='initialize_instance'),
  CHECK(("client_ref__state"=2 AND "client_ref" IS NOT NULL) OR ("client_ref__state" IN (0,1) AND "client_ref" IS NULL)),
  CHECK(("instance__state"=2 AND "instance" IS NOT NULL) OR ("instance__state" IN (0,1) AND "instance" IS NULL)),
  CHECK(("start__state"=2 AND "start" IS NOT NULL) OR ("start__state" IN (0,1) AND "start" IS NULL)),
  CHECK(("definition__state"=2 AND "definition" IS NOT NULL) OR ("definition__state" IN (0,1) AND "definition" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL))
) STRICT;

CREATE TABLE "r_stored_context" (
  __row_id INTEGER PRIMARY KEY,
  "owner__state" INTEGER NOT NULL CHECK("owner__state" IN (2)),
  "owner" TEXT,
  "scope__state" INTEGER NOT NULL CHECK("scope__state" IN (2)),
  "scope" TEXT,
  "expires__state" INTEGER NOT NULL CHECK("expires__state" IN (2)),
  "expires" TEXT,
  "frame__state" INTEGER NOT NULL CHECK("frame__state" IN (2)),
  "frame" INTEGER REFERENCES "r_frame"(__row_id),
  CHECK(("owner__state"=2 AND "owner" IS NOT NULL) OR ("owner__state" IN (0,1) AND "owner" IS NULL)),
  CHECK(("scope__state"=2 AND "scope" IS NOT NULL) OR ("scope__state" IN (0,1) AND "scope" IS NULL)),
  CHECK(("expires__state"=2 AND "expires" IS NOT NULL) OR ("expires__state" IN (0,1) AND "expires" IS NULL)),
  CHECK(("frame__state"=2 AND "frame" IS NOT NULL) OR ("frame__state" IN (0,1) AND "frame" IS NULL))
) STRICT;

CREATE TABLE "r_frame" (
  __row_id INTEGER PRIMARY KEY,
  "universe__state" INTEGER NOT NULL CHECK("universe__state" IN (2)),
  "universe" TEXT,
  "continuity__state" INTEGER NOT NULL CHECK("continuity__state" IN (2)),
  "continuity" TEXT,
  "revision__state" INTEGER NOT NULL CHECK("revision__state" IN (2)),
  "revision" TEXT,
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (2)),
  "context" INTEGER REFERENCES "r_record_ref"(__row_id),
  "time__state" INTEGER NOT NULL CHECK("time__state" IN (2)),
  "time" INTEGER REFERENCES "r_frame_time"(__row_id),
  "perspective__state" INTEGER NOT NULL CHECK("perspective__state" IN (2)),
  "perspective" INTEGER REFERENCES "r_perspective"(__row_id),
  "readerScene__state" INTEGER NOT NULL CHECK("readerScene__state" IN (0,1,2)),
  "readerScene" INTEGER REFERENCES "r_frame_reader_scene"(__row_id),
  "personalSequence__state" INTEGER NOT NULL CHECK("personalSequence__state" IN (0,1,2)),
  "personalSequence" INTEGER REFERENCES "r_frame_personal_sequence"(__row_id),
  CHECK(("universe__state"=2 AND "universe" IS NOT NULL) OR ("universe__state" IN (0,1) AND "universe" IS NULL)),
  CHECK(("continuity__state"=2 AND "continuity" IS NOT NULL) OR ("continuity__state" IN (0,1) AND "continuity" IS NULL)),
  CHECK(("revision__state"=2 AND "revision" IS NOT NULL) OR ("revision__state" IN (0,1) AND "revision" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("time__state"=2 AND "time" IS NOT NULL) OR ("time__state" IN (0,1) AND "time" IS NULL)),
  CHECK(("perspective__state"=2 AND "perspective" IS NOT NULL) OR ("perspective__state" IN (0,1) AND "perspective" IS NULL)),
  CHECK(("readerScene__state"=2 AND "readerScene" IS NOT NULL) OR ("readerScene__state" IN (0,1) AND "readerScene" IS NULL)),
  CHECK(("personalSequence__state"=2 AND "personalSequence" IS NOT NULL) OR ("personalSequence__state" IN (0,1) AND "personalSequence" IS NULL))
) STRICT;

CREATE TABLE "r_frame_time" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 2),
  v0 INTEGER REFERENCES "r_frame_time_v0"(__row_id),
  v1 INTEGER REFERENCES "r_frame_time_v1"(__row_id),
  v2 INTEGER REFERENCES "r_frame_time_v2"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL)
) STRICT;

CREATE TABLE "r_frame_time_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='timeless')
) STRICT;

CREATE TABLE "r_frame_time_v1" (
  __row_id INTEGER PRIMARY KEY,
  "time__state" INTEGER NOT NULL CHECK("time__state" IN (2)),
  "time" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("time__state"=2 AND "time" IS NOT NULL) OR ("time__state" IN (0,1) AND "time" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='at')
) STRICT;

CREATE TABLE "r_frame_time_v2" (
  __row_id INTEGER PRIMARY KEY,
  "event__state" INTEGER NOT NULL CHECK("event__state" IN (2)),
  "event" INTEGER REFERENCES "r_record_ref"(__row_id),
  "side__state" INTEGER NOT NULL CHECK("side__state" IN (2)),
  "side" INTEGER REFERENCES "r_event_time_side"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("event__state"=2 AND "event" IS NOT NULL) OR ("event__state" IN (0,1) AND "event" IS NULL)),
  CHECK(("side__state"=2 AND "side" IS NOT NULL) OR ("side__state" IN (0,1) AND "side" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='at_event')
) STRICT;

CREATE TABLE "r_event_time_side" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_perspective" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 3),
  v0 TEXT,
  v1 INTEGER REFERENCES "r_perspective_v1"(__row_id),
  v2 INTEGER REFERENCES "r_perspective_v2"(__row_id),
  v3 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL)
) STRICT;

CREATE TABLE "r_perspective_v1" (
  __row_id INTEGER PRIMARY KEY,
  "character__state" INTEGER NOT NULL CHECK("character__state" IN (2)),
  "character" TEXT,
  CHECK(("character__state"=2 AND "character" IS NOT NULL) OR ("character__state" IN (0,1) AND "character" IS NULL))
) STRICT;

CREATE TABLE "r_perspective_v2" (
  __row_id INTEGER PRIMARY KEY,
  "narrator__state" INTEGER NOT NULL CHECK("narrator__state" IN (2)),
  "narrator" TEXT,
  CHECK(("narrator__state"=2 AND "narrator" IS NOT NULL) OR ("narrator__state" IN (0,1) AND "narrator" IS NULL))
) STRICT;

CREATE TABLE "r_frame_reader_scene" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_frame_personal_sequence" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_stored_proposal" (
  __row_id INTEGER PRIMARY KEY,
  "proposal__state" INTEGER NOT NULL CHECK("proposal__state" IN (2)),
  "proposal" INTEGER REFERENCES "r_proposal"(__row_id),
  "owner__state" INTEGER NOT NULL CHECK("owner__state" IN (2)),
  "owner" TEXT,
  "author_origin__state" INTEGER NOT NULL CHECK("author_origin__state" IN (2)),
  "author_origin" INTEGER,
  "changes__state" INTEGER NOT NULL CHECK("changes__state" IN (2)),
  "changes" INTEGER REFERENCES "r_stored_proposal_changes"(__row_id),
  "footprint__state" INTEGER NOT NULL CHECK("footprint__state" IN (2)),
  "footprint" INTEGER REFERENCES "r_footprint"(__row_id),
  CHECK(("proposal__state"=2 AND "proposal" IS NOT NULL) OR ("proposal__state" IN (0,1) AND "proposal" IS NULL)),
  CHECK(("owner__state"=2 AND "owner" IS NOT NULL) OR ("owner__state" IN (0,1) AND "owner" IS NULL)),
  CHECK(("author_origin__state"=2 AND "author_origin" IS NOT NULL) OR ("author_origin__state" IN (0,1) AND "author_origin" IS NULL)),
  CHECK("author_origin" IN (0,1)),
  CHECK(("changes__state"=2 AND "changes" IS NOT NULL) OR ("changes__state" IN (0,1) AND "changes" IS NULL)),
  CHECK(("footprint__state"=2 AND "footprint" IS NOT NULL) OR ("footprint__state" IN (0,1) AND "footprint" IS NULL))
) STRICT;

CREATE TABLE "r_proposal" (
  __row_id INTEGER PRIMARY KEY,
  "base_frame__state" INTEGER NOT NULL CHECK("base_frame__state" IN (2)),
  "base_frame" INTEGER REFERENCES "r_frame"(__row_id),
  "world_scope__state" INTEGER NOT NULL CHECK("world_scope__state" IN (0,1,2)),
  "world_scope" INTEGER REFERENCES "r_proposal_world_scope"(__row_id),
  "proposal_id__state" INTEGER NOT NULL CHECK("proposal_id__state" IN (2)),
  "proposal_id" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  "submission__state" INTEGER NOT NULL CHECK("submission__state" IN (2)),
  "submission" TEXT,
  "operations__state" INTEGER NOT NULL CHECK("operations__state" IN (2)),
  "operations" INTEGER REFERENCES "r_proposal_operations"(__row_id),
  "compiled_changes__state" INTEGER NOT NULL CHECK("compiled_changes__state" IN (0,2)),
  "compiled_changes" INTEGER REFERENCES "r_proposal_compiled_changes"(__row_id),
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "canonical__state" INTEGER NOT NULL CHECK("canonical__state" IN (2)),
  "canonical" INTEGER,
  "operation_id__state" INTEGER NOT NULL CHECK("operation_id__state" IN (2)),
  "operation_id" TEXT,
  "withdrawn__state" INTEGER NOT NULL CHECK("withdrawn__state" IN (2)),
  "withdrawn" INTEGER,
  CHECK(("base_frame__state"=2 AND "base_frame" IS NOT NULL) OR ("base_frame__state" IN (0,1) AND "base_frame" IS NULL)),
  CHECK(("world_scope__state"=2 AND "world_scope" IS NOT NULL) OR ("world_scope__state" IN (0,1) AND "world_scope" IS NULL)),
  CHECK(("proposal_id__state"=2 AND "proposal_id" IS NOT NULL) OR ("proposal_id__state" IN (0,1) AND "proposal_id" IS NULL)),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL)),
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL)),
  CHECK(("submission__state"=2 AND "submission" IS NOT NULL) OR ("submission__state" IN (0,1) AND "submission" IS NULL)),
  CHECK("submission" IN ('draft','submitted')),
  CHECK(("operations__state"=2 AND "operations" IS NOT NULL) OR ("operations__state" IN (0,1) AND "operations" IS NULL)),
  CHECK(("compiled_changes__state"=2 AND "compiled_changes" IS NOT NULL) OR ("compiled_changes__state" IN (0,1) AND "compiled_changes" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("canonical__state"=2 AND "canonical" IS NOT NULL) OR ("canonical__state" IN (0,1) AND "canonical" IS NULL)),
  CHECK("canonical" IN (0,1)),
  CHECK(("operation_id__state"=2 AND "operation_id" IS NOT NULL) OR ("operation_id__state" IN (0,1) AND "operation_id" IS NULL)),
  CHECK(("withdrawn__state"=2 AND "withdrawn" IS NOT NULL) OR ("withdrawn__state" IN (0,1) AND "withdrawn" IS NULL)),
  CHECK("withdrawn" IN (0,1))
) STRICT;

CREATE TABLE "r_proposal_world_scope" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_proposal_operations" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_proposal_operations_items" (owner INTEGER NOT NULL REFERENCES "r_proposal_operations"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_domain_operation"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_proposal_compiled_changes" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_proposal_compiled_changes_items" (owner INTEGER NOT NULL REFERENCES "r_proposal_compiled_changes"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_compiled_change"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_compiled_change" (
  __row_id INTEGER PRIMARY KEY,
  "record_id__state" INTEGER NOT NULL CHECK("record_id__state" IN (2)),
  "record_id" TEXT,
  "expected__state" INTEGER NOT NULL CHECK("expected__state" IN (0,1,2)),
  "expected" INTEGER REFERENCES "r_compiled_change_expected"(__row_id),
  "next__state" INTEGER NOT NULL CHECK("next__state" IN (0,1,2)),
  "next" INTEGER REFERENCES "r_compiled_change_next"(__row_id),
  CHECK(("record_id__state"=2 AND "record_id" IS NOT NULL) OR ("record_id__state" IN (0,1) AND "record_id" IS NULL)),
  CHECK(("expected__state"=2 AND "expected" IS NOT NULL) OR ("expected__state" IN (0,1) AND "expected" IS NULL)),
  CHECK(("next__state"=2 AND "next" IS NOT NULL) OR ("next__state" IN (0,1) AND "next" IS NULL))
) STRICT;

CREATE TABLE "r_compiled_change_expected" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_compiled_change_next" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_version"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_stored_proposal_changes" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_stored_proposal_changes_items" (owner INTEGER NOT NULL REFERENCES "r_stored_proposal_changes"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_assignment"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_assignment" (
  __row_id INTEGER PRIMARY KEY,
  "record_id__state" INTEGER NOT NULL CHECK("record_id__state" IN (2)),
  "record_id" TEXT,
  "expected__state" INTEGER NOT NULL CHECK("expected__state" IN (1,2)),
  "expected" INTEGER REFERENCES "r_assignment_expected"(__row_id),
  "next__state" INTEGER NOT NULL CHECK("next__state" IN (1,2)),
  "next" INTEGER REFERENCES "r_assignment_next"(__row_id),
  CHECK(("record_id__state"=2 AND "record_id" IS NOT NULL) OR ("record_id__state" IN (0,1) AND "record_id" IS NULL)),
  CHECK(("expected__state"=2 AND "expected" IS NOT NULL) OR ("expected__state" IN (0,1) AND "expected" IS NULL)),
  CHECK(("next__state"=2 AND "next" IS NOT NULL) OR ("next__state" IN (0,1) AND "next" IS NULL))
) STRICT;

CREATE TABLE "r_assignment_expected" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_assignment_next" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_version"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_footprint" (
  __row_id INTEGER PRIMARY KEY,
  "worlds__state" INTEGER NOT NULL CHECK("worlds__state" IN (2)),
  "worlds" INTEGER REFERENCES "r_footprint_worlds"(__row_id),
  "shared__state" INTEGER NOT NULL CHECK("shared__state" IN (2)),
  "shared" INTEGER,
  "protected__state" INTEGER NOT NULL CHECK("protected__state" IN (2)),
  "protected" INTEGER,
  CHECK(("worlds__state"=2 AND "worlds" IS NOT NULL) OR ("worlds__state" IN (0,1) AND "worlds" IS NULL)),
  CHECK(("shared__state"=2 AND "shared" IS NOT NULL) OR ("shared__state" IN (0,1) AND "shared" IS NULL)),
  CHECK("shared" IN (0,1)),
  CHECK(("protected__state"=2 AND "protected" IS NOT NULL) OR ("protected__state" IN (0,1) AND "protected" IS NULL)),
  CHECK("protected" IN (0,1))
) STRICT;

CREATE TABLE "r_footprint_worlds" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_footprint_worlds_items" (owner INTEGER NOT NULL REFERENCES "r_footprint_worlds"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_checked" (
  __row_id INTEGER PRIMARY KEY,
  "proposal_digest__state" INTEGER NOT NULL CHECK("proposal_digest__state" IN (2)),
  "proposal_digest" TEXT,
  "validation__state" INTEGER NOT NULL CHECK("validation__state" IN (2)),
  "validation" INTEGER REFERENCES "r_validation"(__row_id),
  "admissible__state" INTEGER NOT NULL CHECK("admissible__state" IN (2)),
  "admissible" INTEGER,
  "report__state" INTEGER NOT NULL CHECK("report__state" IN (0,1,2)),
  "report" INTEGER REFERENCES "r_checked_report"(__row_id),
  "capture__state" INTEGER NOT NULL CHECK("capture__state" IN (0,1,2)),
  "capture" INTEGER REFERENCES "r_checked_capture"(__row_id),
  CHECK(("proposal_digest__state"=2 AND "proposal_digest" IS NOT NULL) OR ("proposal_digest__state" IN (0,1) AND "proposal_digest" IS NULL)),
  CHECK(("validation__state"=2 AND "validation" IS NOT NULL) OR ("validation__state" IN (0,1) AND "validation" IS NULL)),
  CHECK(("admissible__state"=2 AND "admissible" IS NOT NULL) OR ("admissible__state" IN (0,1) AND "admissible" IS NULL)),
  CHECK("admissible" IN (0,1)),
  CHECK(("report__state"=2 AND "report" IS NOT NULL) OR ("report__state" IN (0,1) AND "report" IS NULL)),
  CHECK(("capture__state"=2 AND "capture" IS NOT NULL) OR ("capture__state" IN (0,1) AND "capture" IS NULL))
) STRICT;

CREATE TABLE "r_validation" (
  __row_id INTEGER PRIMARY KEY,
  "operation_id__state" INTEGER NOT NULL CHECK("operation_id__state" IN (0,1,2)),
  "operation_id" INTEGER REFERENCES "r_validation_operation_id"(__row_id),
  "run_id__state" INTEGER NOT NULL CHECK("run_id__state" IN (2)),
  "run_id" TEXT,
  "coverage__state" INTEGER NOT NULL CHECK("coverage__state" IN (2)),
  "coverage" TEXT,
  "findings__state" INTEGER NOT NULL CHECK("findings__state" IN (2)),
  "findings" INTEGER REFERENCES "r_validation_findings"(__row_id),
  "opposing_evidence__state" INTEGER NOT NULL CHECK("opposing_evidence__state" IN (0,2)),
  "opposing_evidence" INTEGER REFERENCES "r_validation_opposing_evidence"(__row_id),
  "unsupported_capabilities__state" INTEGER NOT NULL CHECK("unsupported_capabilities__state" IN (2)),
  "unsupported_capabilities" INTEGER REFERENCES "r_validation_unsupported_capabilities"(__row_id),
  "input_digest__state" INTEGER NOT NULL CHECK("input_digest__state" IN (2)),
  "input_digest" TEXT,
  "evaluator_version__state" INTEGER NOT NULL CHECK("evaluator_version__state" IN (2)),
  "evaluator_version" TEXT,
  CHECK(("operation_id__state"=2 AND "operation_id" IS NOT NULL) OR ("operation_id__state" IN (0,1) AND "operation_id" IS NULL)),
  CHECK(("run_id__state"=2 AND "run_id" IS NOT NULL) OR ("run_id__state" IN (0,1) AND "run_id" IS NULL)),
  CHECK(("coverage__state"=2 AND "coverage" IS NOT NULL) OR ("coverage__state" IN (0,1) AND "coverage" IS NULL)),
  CHECK("coverage" IN ('complete','partial','unsupported','restricted','failed')),
  CHECK(("findings__state"=2 AND "findings" IS NOT NULL) OR ("findings__state" IN (0,1) AND "findings" IS NULL)),
  CHECK(("opposing_evidence__state"=2 AND "opposing_evidence" IS NOT NULL) OR ("opposing_evidence__state" IN (0,1) AND "opposing_evidence" IS NULL)),
  CHECK(("unsupported_capabilities__state"=2 AND "unsupported_capabilities" IS NOT NULL) OR ("unsupported_capabilities__state" IN (0,1) AND "unsupported_capabilities" IS NULL)),
  CHECK(("input_digest__state"=2 AND "input_digest" IS NOT NULL) OR ("input_digest__state" IN (0,1) AND "input_digest" IS NULL)),
  CHECK(("evaluator_version__state"=2 AND "evaluator_version" IS NOT NULL) OR ("evaluator_version__state" IN (0,1) AND "evaluator_version" IS NULL))
) STRICT;

CREATE TABLE "r_validation_operation_id" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_validation_findings" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_validation_findings_items" (owner INTEGER NOT NULL REFERENCES "r_validation_findings"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_finding"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_finding" (
  __row_id INTEGER PRIMARY KEY,
  "fingerprint__state" INTEGER NOT NULL CHECK("fingerprint__state" IN (2)),
  "fingerprint" TEXT,
  "rule_id__state" INTEGER NOT NULL CHECK("rule_id__state" IN (2)),
  "rule_id" TEXT,
  "outcome__state" INTEGER NOT NULL CHECK("outcome__state" IN (2)),
  "outcome" TEXT,
  "evidence__state" INTEGER NOT NULL CHECK("evidence__state" IN (2)),
  "evidence" INTEGER REFERENCES "r_finding_evidence"(__row_id),
  "coverage__state" INTEGER NOT NULL CHECK("coverage__state" IN (2)),
  "coverage" TEXT,
  CHECK(("fingerprint__state"=2 AND "fingerprint" IS NOT NULL) OR ("fingerprint__state" IN (0,1) AND "fingerprint" IS NULL)),
  CHECK(("rule_id__state"=2 AND "rule_id" IS NOT NULL) OR ("rule_id__state" IN (0,1) AND "rule_id" IS NULL)),
  CHECK(("outcome__state"=2 AND "outcome" IS NOT NULL) OR ("outcome__state" IN (0,1) AND "outcome" IS NULL)),
  CHECK("outcome" IN ('supported','refuted','conflicting','not_established')),
  CHECK(("evidence__state"=2 AND "evidence" IS NOT NULL) OR ("evidence__state" IN (0,1) AND "evidence" IS NULL)),
  CHECK(("coverage__state"=2 AND "coverage" IS NOT NULL) OR ("coverage__state" IN (0,1) AND "coverage" IS NULL)),
  CHECK("coverage" IN ('complete','partial','unsupported','restricted','failed'))
) STRICT;

CREATE TABLE "r_finding_evidence" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_finding_evidence_items" (owner INTEGER NOT NULL REFERENCES "r_finding_evidence"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_validation_opposing_evidence" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_validation_opposing_evidence_items" (owner INTEGER NOT NULL REFERENCES "r_validation_opposing_evidence"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_opposing_evidence"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_opposing_evidence" (
  __row_id INTEGER PRIMARY KEY,
  "diagnostic_version__state" INTEGER NOT NULL CHECK("diagnostic_version__state" IN (2)),
  "diagnostic_version" TEXT,
  "fingerprint__state" INTEGER NOT NULL CHECK("fingerprint__state" IN (2)),
  "fingerprint" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" INTEGER REFERENCES "r_proposition"(__row_id),
  "support__state" INTEGER NOT NULL CHECK("support__state" IN (2)),
  "support" INTEGER REFERENCES "r_opposing_chain"(__row_id),
  "refutation__state" INTEGER NOT NULL CHECK("refutation__state" IN (2)),
  "refutation" INTEGER REFERENCES "r_opposing_chain"(__row_id),
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (2)),
  "context" INTEGER REFERENCES "r_record_ref"(__row_id),
  "applicability__state" INTEGER NOT NULL CHECK("applicability__state" IN (0,1,2)),
  "applicability" INTEGER REFERENCES "r_opposing_evidence_applicability"(__row_id),
  "realm__state" INTEGER NOT NULL CHECK("realm__state" IN (0,1,2)),
  "realm" INTEGER REFERENCES "r_opposing_evidence_realm"(__row_id),
  "intersection__state" INTEGER NOT NULL CHECK("intersection__state" IN (2)),
  "intersection" INTEGER REFERENCES "r_opposing_intersection"(__row_id),
  "coverage__state" INTEGER NOT NULL CHECK("coverage__state" IN (2)),
  "coverage" TEXT,
  "unresolved_reasons__state" INTEGER NOT NULL CHECK("unresolved_reasons__state" IN (2)),
  "unresolved_reasons" INTEGER REFERENCES "r_opposing_evidence_unresolved_reasons"(__row_id),
  "policy_versions__state" INTEGER NOT NULL CHECK("policy_versions__state" IN (2)),
  "policy_versions" INTEGER REFERENCES "r_opposing_evidence_policy_versions"(__row_id),
  "exception_versions__state" INTEGER NOT NULL CHECK("exception_versions__state" IN (2)),
  "exception_versions" INTEGER REFERENCES "r_opposing_evidence_exception_versions"(__row_id),
  CHECK(("diagnostic_version__state"=2 AND "diagnostic_version" IS NOT NULL) OR ("diagnostic_version__state" IN (0,1) AND "diagnostic_version" IS NULL)),
  CHECK(("fingerprint__state"=2 AND "fingerprint" IS NOT NULL) OR ("fingerprint__state" IN (0,1) AND "fingerprint" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind" IN ('definite','unresolved')),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("support__state"=2 AND "support" IS NOT NULL) OR ("support__state" IN (0,1) AND "support" IS NULL)),
  CHECK(("refutation__state"=2 AND "refutation" IS NOT NULL) OR ("refutation__state" IN (0,1) AND "refutation" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("applicability__state"=2 AND "applicability" IS NOT NULL) OR ("applicability__state" IN (0,1) AND "applicability" IS NULL)),
  CHECK(("realm__state"=2 AND "realm" IS NOT NULL) OR ("realm__state" IN (0,1) AND "realm" IS NULL)),
  CHECK(("intersection__state"=2 AND "intersection" IS NOT NULL) OR ("intersection__state" IN (0,1) AND "intersection" IS NULL)),
  CHECK(("coverage__state"=2 AND "coverage" IS NOT NULL) OR ("coverage__state" IN (0,1) AND "coverage" IS NULL)),
  CHECK("coverage" IN ('complete','partial','unsupported','restricted','failed')),
  CHECK(("unresolved_reasons__state"=2 AND "unresolved_reasons" IS NOT NULL) OR ("unresolved_reasons__state" IN (0,1) AND "unresolved_reasons" IS NULL)),
  CHECK(("policy_versions__state"=2 AND "policy_versions" IS NOT NULL) OR ("policy_versions__state" IN (0,1) AND "policy_versions" IS NULL)),
  CHECK(("exception_versions__state"=2 AND "exception_versions" IS NOT NULL) OR ("exception_versions__state" IN (0,1) AND "exception_versions" IS NULL))
) STRICT;

CREATE TABLE "r_opposing_chain" (
  __row_id INTEGER PRIMARY KEY,
  "assertion_id__state" INTEGER NOT NULL CHECK("assertion_id__state" IN (2)),
  "assertion_id" TEXT,
  "proposition_id__state" INTEGER NOT NULL CHECK("proposition_id__state" IN (2)),
  "proposition_id" TEXT,
  "assertion__state" INTEGER NOT NULL CHECK("assertion__state" IN (2)),
  "assertion" TEXT,
  "proposition__state" INTEGER NOT NULL CHECK("proposition__state" IN (2)),
  "proposition" TEXT,
  "dependencies__state" INTEGER NOT NULL CHECK("dependencies__state" IN (2)),
  "dependencies" INTEGER REFERENCES "r_opposing_chain_dependencies"(__row_id),
  "complete__state" INTEGER NOT NULL CHECK("complete__state" IN (2)),
  "complete" INTEGER,
  CHECK(("assertion_id__state"=2 AND "assertion_id" IS NOT NULL) OR ("assertion_id__state" IN (0,1) AND "assertion_id" IS NULL)),
  CHECK(("proposition_id__state"=2 AND "proposition_id" IS NOT NULL) OR ("proposition_id__state" IN (0,1) AND "proposition_id" IS NULL)),
  CHECK(("assertion__state"=2 AND "assertion" IS NOT NULL) OR ("assertion__state" IN (0,1) AND "assertion" IS NULL)),
  CHECK(("proposition__state"=2 AND "proposition" IS NOT NULL) OR ("proposition__state" IN (0,1) AND "proposition" IS NULL)),
  CHECK(("dependencies__state"=2 AND "dependencies" IS NOT NULL) OR ("dependencies__state" IN (0,1) AND "dependencies" IS NULL)),
  CHECK(("complete__state"=2 AND "complete" IS NOT NULL) OR ("complete__state" IN (0,1) AND "complete" IS NULL)),
  CHECK("complete" IN (0,1))
) STRICT;

CREATE TABLE "r_opposing_chain_dependencies" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_opposing_chain_dependencies_items" (owner INTEGER NOT NULL REFERENCES "r_opposing_chain_dependencies"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_version_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_opposing_evidence_applicability" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_applicability"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_opposing_evidence_realm" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_record_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_opposing_intersection" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 3),
  v0 INTEGER REFERENCES "r_opposing_intersection_v0"(__row_id),
  v1 INTEGER REFERENCES "r_opposing_intersection_v1"(__row_id),
  v2 INTEGER REFERENCES "r_opposing_intersection_v2"(__row_id),
  v3 INTEGER REFERENCES "r_opposing_intersection_v3"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL)
) STRICT;

CREATE TABLE "r_opposing_intersection_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unqualified')
) STRICT;

CREATE TABLE "r_opposing_intersection_v1" (
  __row_id INTEGER PRIMARY KEY,
  "validity__state" INTEGER NOT NULL CHECK("validity__state" IN (2)),
  "validity" INTEGER REFERENCES "r_validity"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("validity__state"=2 AND "validity" IS NOT NULL) OR ("validity__state" IN (0,1) AND "validity" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='exact')
) STRICT;

CREATE TABLE "r_opposing_intersection_v2" (
  __row_id INTEGER PRIMARY KEY,
  "left__state" INTEGER NOT NULL CHECK("left__state" IN (2)),
  "left" INTEGER REFERENCES "r_validity"(__row_id),
  "right__state" INTEGER NOT NULL CHECK("right__state" IN (2)),
  "right" INTEGER REFERENCES "r_validity"(__row_id),
  "guaranteed__state" INTEGER NOT NULL CHECK("guaranteed__state" IN (0,1,2)),
  "guaranteed" INTEGER REFERENCES "r_opposing_intersection_v2_guaranteed"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("left__state"=2 AND "left" IS NOT NULL) OR ("left__state" IN (0,1) AND "left" IS NULL)),
  CHECK(("right__state"=2 AND "right" IS NOT NULL) OR ("right__state" IN (0,1) AND "right" IS NULL)),
  CHECK(("guaranteed__state"=2 AND "guaranteed" IS NOT NULL) OR ("guaranteed__state" IN (0,1) AND "guaranteed" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='uncertain')
) STRICT;

CREATE TABLE "r_opposing_intersection_v2_guaranteed" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_validity"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_opposing_intersection_v3" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unresolved')
) STRICT;

CREATE TABLE "r_opposing_evidence_unresolved_reasons" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_opposing_evidence_unresolved_reasons_items" (owner INTEGER NOT NULL REFERENCES "r_opposing_evidence_unresolved_reasons"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_opposing_evidence_policy_versions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_opposing_evidence_policy_versions_items" (owner INTEGER NOT NULL REFERENCES "r_opposing_evidence_policy_versions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_opposing_evidence_exception_versions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_opposing_evidence_exception_versions_items" (owner INTEGER NOT NULL REFERENCES "r_opposing_evidence_exception_versions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_validation_unsupported_capabilities" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_validation_unsupported_capabilities_items" (owner INTEGER NOT NULL REFERENCES "r_validation_unsupported_capabilities"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_checked_report" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_validation_report"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_validation_report" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_validation_report_v0"(__row_id),
  v1 INTEGER REFERENCES "r_validation_report_v1"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL)
) STRICT;

CREATE TABLE "r_validation_report_v0" (
  __row_id INTEGER PRIMARY KEY,
  "execution__state" INTEGER NOT NULL CHECK("execution__state" IN (2)),
  "execution" INTEGER REFERENCES "r_validation"(__row_id),
  "submitted_input__state" INTEGER NOT NULL CHECK("submitted_input__state" IN (2)),
  "submitted_input" INTEGER REFERENCES "r_submitted_input"(__row_id),
  "assessment__state" INTEGER NOT NULL CHECK("assessment__state" IN (2)),
  "assessment" INTEGER REFERENCES "r_assessment_state"(__row_id),
  "final_binding_digest__state" INTEGER NOT NULL CHECK("final_binding_digest__state" IN (1,2)),
  "final_binding_digest" INTEGER REFERENCES "r_validation_report_v0_final_binding_digest"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("execution__state"=2 AND "execution" IS NOT NULL) OR ("execution__state" IN (0,1) AND "execution" IS NULL)),
  CHECK(("submitted_input__state"=2 AND "submitted_input" IS NOT NULL) OR ("submitted_input__state" IN (0,1) AND "submitted_input" IS NULL)),
  CHECK(("assessment__state"=2 AND "assessment" IS NOT NULL) OR ("assessment__state" IN (0,1) AND "assessment" IS NULL)),
  CHECK(("final_binding_digest__state"=2 AND "final_binding_digest" IS NOT NULL) OR ("final_binding_digest__state" IN (0,1) AND "final_binding_digest" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='evaluated')
) STRICT;

CREATE TABLE "r_submitted_input" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 2),
  v0 INTEGER REFERENCES "r_submitted_input_v0"(__row_id),
  v1 INTEGER REFERENCES "r_submitted_input_v1"(__row_id),
  v2 INTEGER REFERENCES "r_submitted_input_v2"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL)
) STRICT;

CREATE TABLE "r_submitted_input_v0" (
  __row_id INTEGER PRIMARY KEY,
  "frame__state" INTEGER NOT NULL CHECK("frame__state" IN (2)),
  "frame" INTEGER REFERENCES "r_frame"(__row_id),
  "check_scope__state" INTEGER NOT NULL CHECK("check_scope__state" IN (2)),
  "check_scope" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("frame__state"=2 AND "frame" IS NOT NULL) OR ("frame__state" IN (0,1) AND "frame" IS NULL)),
  CHECK(("check_scope__state"=2 AND "check_scope" IS NOT NULL) OR ("check_scope__state" IN (0,1) AND "check_scope" IS NULL)),
  CHECK("check_scope" IN ('candidate','dependencies','universe')),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='query')
) STRICT;

CREATE TABLE "r_submitted_input_v1" (
  __row_id INTEGER PRIMARY KEY,
  "proposal__state" INTEGER NOT NULL CHECK("proposal__state" IN (2)),
  "proposal" INTEGER REFERENCES "r_proposal_ref"(__row_id),
  "includes_sources__state" INTEGER NOT NULL CHECK("includes_sources__state" IN (2)),
  "includes_sources" INTEGER,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("proposal__state"=2 AND "proposal" IS NOT NULL) OR ("proposal__state" IN (0,1) AND "proposal" IS NULL)),
  CHECK(("includes_sources__state"=2 AND "includes_sources" IS NOT NULL) OR ("includes_sources__state" IN (0,1) AND "includes_sources" IS NULL)),
  CHECK("includes_sources" IN (0,1)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='record_candidate')
) STRICT;

CREATE TABLE "r_proposal_ref" (
  __row_id INTEGER PRIMARY KEY,
  "proposal_id__state" INTEGER NOT NULL CHECK("proposal_id__state" IN (2)),
  "proposal_id" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  CHECK(("proposal_id__state"=2 AND "proposal_id" IS NOT NULL) OR ("proposal_id__state" IN (0,1) AND "proposal_id" IS NULL)),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL)),
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL))
) STRICT;

CREATE TABLE "r_submitted_input_v2" (
  __row_id INTEGER PRIMARY KEY,
  "proposal__state" INTEGER NOT NULL CHECK("proposal__state" IN (2)),
  "proposal" INTEGER REFERENCES "r_proposal_ref"(__row_id),
  "sources__state" INTEGER NOT NULL CHECK("sources__state" IN (2)),
  "sources" INTEGER REFERENCES "r_submitted_input_v2_sources"(__row_id),
  "inventory_digest__state" INTEGER NOT NULL CHECK("inventory_digest__state" IN (2)),
  "inventory_digest" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("proposal__state"=2 AND "proposal" IS NOT NULL) OR ("proposal__state" IN (0,1) AND "proposal" IS NULL)),
  CHECK(("sources__state"=2 AND "sources" IS NOT NULL) OR ("sources__state" IN (0,1) AND "sources" IS NULL)),
  CHECK(("inventory_digest__state"=2 AND "inventory_digest" IS NOT NULL) OR ("inventory_digest__state" IN (0,1) AND "inventory_digest" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='source_assessed_candidate')
) STRICT;

CREATE TABLE "r_submitted_input_v2_sources" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_submitted_input_v2_sources_items" (owner INTEGER NOT NULL REFERENCES "r_submitted_input_v2_sources"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_source_binding"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_source_binding" (
  __row_id INTEGER PRIMARY KEY,
  "key__state" INTEGER NOT NULL CHECK("key__state" IN (2)),
  "key" TEXT,
  "source_version__state" INTEGER NOT NULL CHECK("source_version__state" IN (2)),
  "source_version" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  "blob_digest__state" INTEGER NOT NULL CHECK("blob_digest__state" IN (2)),
  "blob_digest" TEXT,
  "byte_size__state" INTEGER NOT NULL CHECK("byte_size__state" IN (2)),
  "byte_size" TEXT,
  "representation__state" INTEGER NOT NULL CHECK("representation__state" IN (2)),
  "representation" TEXT,
  "ranges__state" INTEGER NOT NULL CHECK("ranges__state" IN (2)),
  "ranges" INTEGER REFERENCES "r_source_binding_ranges"(__row_id),
  "work_edition__state" INTEGER NOT NULL CHECK("work_edition__state" IN (1,2)),
  "work_edition" INTEGER REFERENCES "r_source_binding_work_edition"(__row_id),
  "passage_id__state" INTEGER NOT NULL CHECK("passage_id__state" IN (1,2)),
  "passage_id" INTEGER REFERENCES "r_source_binding_passage_id"(__row_id),
  CHECK(("key__state"=2 AND "key" IS NOT NULL) OR ("key__state" IN (0,1) AND "key" IS NULL)),
  CHECK(("source_version__state"=2 AND "source_version" IS NOT NULL) OR ("source_version__state" IN (0,1) AND "source_version" IS NULL)),
  CHECK(("blob_digest__state"=2 AND "blob_digest" IS NOT NULL) OR ("blob_digest__state" IN (0,1) AND "blob_digest" IS NULL)),
  CHECK(("byte_size__state"=2 AND "byte_size" IS NOT NULL) OR ("byte_size__state" IN (0,1) AND "byte_size" IS NULL)),
  CHECK(("representation__state"=2 AND "representation" IS NOT NULL) OR ("representation__state" IN (0,1) AND "representation" IS NULL)),
  CHECK("representation" IN ('exact-utf8-v1')),
  CHECK(("ranges__state"=2 AND "ranges" IS NOT NULL) OR ("ranges__state" IN (0,1) AND "ranges" IS NULL)),
  CHECK(("work_edition__state"=2 AND "work_edition" IS NOT NULL) OR ("work_edition__state" IN (0,1) AND "work_edition" IS NULL)),
  CHECK(("passage_id__state"=2 AND "passage_id" IS NOT NULL) OR ("passage_id__state" IN (0,1) AND "passage_id" IS NULL))
) STRICT;

CREATE TABLE "r_assessment_version_ref" (
  __row_id INTEGER PRIMARY KEY,
  "universe__state" INTEGER NOT NULL CHECK("universe__state" IN (2)),
  "universe" TEXT,
  "record__state" INTEGER NOT NULL CHECK("record__state" IN (2)),
  "record" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  CHECK(("universe__state"=2 AND "universe" IS NOT NULL) OR ("universe__state" IN (0,1) AND "universe" IS NULL)),
  CHECK(("record__state"=2 AND "record" IS NOT NULL) OR ("record__state" IN (0,1) AND "record" IS NULL)),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL))
) STRICT;

CREATE TABLE "r_source_binding_ranges" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_source_binding_ranges_items" (owner INTEGER NOT NULL REFERENCES "r_source_binding_ranges"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_byte_range"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_byte_range" (
  __row_id INTEGER PRIMARY KEY,
  "start__state" INTEGER NOT NULL CHECK("start__state" IN (2)),
  "start" TEXT,
  "end__state" INTEGER NOT NULL CHECK("end__state" IN (2)),
  "end" TEXT,
  CHECK(("start__state"=2 AND "start" IS NOT NULL) OR ("start__state" IN (0,1) AND "start" IS NULL)),
  CHECK(("end__state"=2 AND "end" IS NOT NULL) OR ("end__state" IN (0,1) AND "end" IS NULL))
) STRICT;

CREATE TABLE "r_source_binding_work_edition" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_source_binding_passage_id" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_assessment_state" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 4),
  v0 INTEGER REFERENCES "r_assessment_state_v0"(__row_id),
  v1 INTEGER REFERENCES "r_assessment_state_v1"(__row_id),
  v2 INTEGER REFERENCES "r_assessment_state_v2"(__row_id),
  v3 INTEGER REFERENCES "r_assessment_state_v3"(__row_id),
  v4 INTEGER REFERENCES "r_assessment_state_v4"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL),
  CHECK(variant=4 OR v4 IS NULL),
  CHECK(variant!=4 OR v4 IS NOT NULL)
) STRICT;

CREATE TABLE "r_assessment_state_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='absent')
) STRICT;

CREATE TABLE "r_assessment_state_v1" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unavailable_legacy')
) STRICT;

CREATE TABLE "r_assessment_state_v2" (
  __row_id INTEGER PRIMARY KEY,
  "reason__state" INTEGER NOT NULL CHECK("reason__state" IN (2)),
  "reason" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("reason__state"=2 AND "reason" IS NOT NULL) OR ("reason__state" IN (0,1) AND "reason" IS NULL)),
  CHECK("reason" IN ('missing_retained_material','unsupported_representation','failed_or_cancelled_check')),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unavailable')
) STRICT;

CREATE TABLE "r_assessment_state_v3" (
  __row_id INTEGER PRIMARY KEY,
  "assessment_reference__state" INTEGER NOT NULL CHECK("assessment_reference__state" IN (2)),
  "assessment_reference" INTEGER REFERENCES "r_assessment_ref"(__row_id),
  "reasons__state" INTEGER NOT NULL CHECK("reasons__state" IN (2)),
  "reasons" INTEGER REFERENCES "r_assessment_state_v3_reasons"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("assessment_reference__state"=2 AND "assessment_reference" IS NOT NULL) OR ("assessment_reference__state" IN (0,1) AND "assessment_reference" IS NULL)),
  CHECK(("reasons__state"=2 AND "reasons" IS NOT NULL) OR ("reasons__state" IN (0,1) AND "reasons" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='stale')
) STRICT;

CREATE TABLE "r_assessment_ref" (
  __row_id INTEGER PRIMARY KEY,
  "assessment_id__state" INTEGER NOT NULL CHECK("assessment_id__state" IN (2)),
  "assessment_id" TEXT,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  CHECK(("assessment_id__state"=2 AND "assessment_id" IS NOT NULL) OR ("assessment_id__state" IN (0,1) AND "assessment_id" IS NULL)),
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL))
) STRICT;

CREATE TABLE "r_assessment_state_v3_reasons" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_assessment_state_v3_reasons_items" (owner INTEGER NOT NULL REFERENCES "r_assessment_state_v3_reasons"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_assessment_state_v4" (
  __row_id INTEGER PRIMARY KEY,
  "assessment_reference__state" INTEGER NOT NULL CHECK("assessment_reference__state" IN (2)),
  "assessment_reference" INTEGER REFERENCES "r_assessment_ref"(__row_id),
  "selection_generation__state" INTEGER NOT NULL CHECK("selection_generation__state" IN (2)),
  "selection_generation" TEXT,
  "byte_verification__state" INTEGER NOT NULL CHECK("byte_verification__state" IN (2)),
  "byte_verification" TEXT,
  "declared_conclusion__state" INTEGER NOT NULL CHECK("declared_conclusion__state" IN (2)),
  "declared_conclusion" TEXT,
  "inventory_count__state" INTEGER NOT NULL CHECK("inventory_count__state" IN (2)),
  "inventory_count" TEXT,
  "mapping_count__state" INTEGER NOT NULL CHECK("mapping_count__state" IN (2)),
  "mapping_count" TEXT,
  "unresolved_count__state" INTEGER NOT NULL CHECK("unresolved_count__state" IN (2)),
  "unresolved_count" TEXT,
  "inventory_digest__state" INTEGER NOT NULL CHECK("inventory_digest__state" IN (2)),
  "inventory_digest" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("assessment_reference__state"=2 AND "assessment_reference" IS NOT NULL) OR ("assessment_reference__state" IN (0,1) AND "assessment_reference" IS NULL)),
  CHECK(("selection_generation__state"=2 AND "selection_generation" IS NOT NULL) OR ("selection_generation__state" IN (0,1) AND "selection_generation" IS NULL)),
  CHECK(("byte_verification__state"=2 AND "byte_verification" IS NOT NULL) OR ("byte_verification__state" IN (0,1) AND "byte_verification" IS NULL)),
  CHECK("byte_verification" IN ('verified')),
  CHECK(("declared_conclusion__state"=2 AND "declared_conclusion" IS NOT NULL) OR ("declared_conclusion__state" IN (0,1) AND "declared_conclusion" IS NULL)),
  CHECK("declared_conclusion" IN ('consistent_with_declared_inventory','inconsistent','unresolved')),
  CHECK(("inventory_count__state"=2 AND "inventory_count" IS NOT NULL) OR ("inventory_count__state" IN (0,1) AND "inventory_count" IS NULL)),
  CHECK(("mapping_count__state"=2 AND "mapping_count" IS NOT NULL) OR ("mapping_count__state" IN (0,1) AND "mapping_count" IS NULL)),
  CHECK(("unresolved_count__state"=2 AND "unresolved_count" IS NOT NULL) OR ("unresolved_count__state" IN (0,1) AND "unresolved_count" IS NULL)),
  CHECK(("inventory_digest__state"=2 AND "inventory_digest" IS NOT NULL) OR ("inventory_digest__state" IN (0,1) AND "inventory_digest" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='bound')
) STRICT;

CREATE TABLE "r_validation_report_v0_final_binding_digest" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_validation_report_v1" (
  __row_id INTEGER PRIMARY KEY,
  "execution_coverage__state" INTEGER NOT NULL CHECK("execution_coverage__state" IN (2)),
  "execution_coverage" TEXT,
  "submitted_input__state" INTEGER NOT NULL CHECK("submitted_input__state" IN (2)),
  "submitted_input" INTEGER REFERENCES "r_restricted_input"(__row_id),
  "assessment__state" INTEGER NOT NULL CHECK("assessment__state" IN (2)),
  "assessment" INTEGER REFERENCES "r_restricted_assessment"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("execution_coverage__state"=2 AND "execution_coverage" IS NOT NULL) OR ("execution_coverage__state" IN (0,1) AND "execution_coverage" IS NULL)),
  CHECK("execution_coverage" IN ('restricted')),
  CHECK(("submitted_input__state"=2 AND "submitted_input" IS NOT NULL) OR ("submitted_input__state" IN (0,1) AND "submitted_input" IS NULL)),
  CHECK(("assessment__state"=2 AND "assessment" IS NOT NULL) OR ("assessment__state" IN (0,1) AND "assessment" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='restricted')
) STRICT;

CREATE TABLE "r_restricted_input" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 0),
  v0 INTEGER REFERENCES "r_restricted_input_v0"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL)
) STRICT;

CREATE TABLE "r_restricted_input_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='restricted')
) STRICT;

CREATE TABLE "r_restricted_assessment" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 0),
  v0 INTEGER REFERENCES "r_restricted_assessment_v0"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL)
) STRICT;

CREATE TABLE "r_restricted_assessment_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='restricted')
) STRICT;

CREATE TABLE "r_checked_capture" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_validation_capture"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_validation_capture" (
  __row_id INTEGER PRIMARY KEY,
  "selection__state" INTEGER NOT NULL CHECK("selection__state" IN (2)),
  "selection" INTEGER REFERENCES "r_assessment_selection"(__row_id),
  "assessment__state" INTEGER NOT NULL CHECK("assessment__state" IN (2)),
  "assessment" INTEGER REFERENCES "r_assessment_state"(__row_id),
  "submitted_input__state" INTEGER NOT NULL CHECK("submitted_input__state" IN (2)),
  "submitted_input" INTEGER REFERENCES "r_submitted_input"(__row_id),
  "head__state" INTEGER NOT NULL CHECK("head__state" IN (2)),
  "head" TEXT,
  "latest_proposal_key__state" INTEGER NOT NULL CHECK("latest_proposal_key__state" IN (1,2)),
  "latest_proposal_key" INTEGER REFERENCES "r_validation_capture_latest_proposal_key"(__row_id),
  "authority_digest__state" INTEGER NOT NULL CHECK("authority_digest__state" IN (2)),
  "authority_digest" TEXT,
  "authority_sequence__state" INTEGER NOT NULL CHECK("authority_sequence__state" IN (0,1,2)),
  "authority_sequence" INTEGER REFERENCES "r_validation_capture_authority_sequence"(__row_id),
  CHECK(("selection__state"=2 AND "selection" IS NOT NULL) OR ("selection__state" IN (0,1) AND "selection" IS NULL)),
  CHECK(("assessment__state"=2 AND "assessment" IS NOT NULL) OR ("assessment__state" IN (0,1) AND "assessment" IS NULL)),
  CHECK(("submitted_input__state"=2 AND "submitted_input" IS NOT NULL) OR ("submitted_input__state" IN (0,1) AND "submitted_input" IS NULL)),
  CHECK(("head__state"=2 AND "head" IS NOT NULL) OR ("head__state" IN (0,1) AND "head" IS NULL)),
  CHECK(("latest_proposal_key__state"=2 AND "latest_proposal_key" IS NOT NULL) OR ("latest_proposal_key__state" IN (0,1) AND "latest_proposal_key" IS NULL)),
  CHECK(("authority_digest__state"=2 AND "authority_digest" IS NOT NULL) OR ("authority_digest__state" IN (0,1) AND "authority_digest" IS NULL)),
  CHECK(("authority_sequence__state"=2 AND "authority_sequence" IS NOT NULL) OR ("authority_sequence__state" IN (0,1) AND "authority_sequence" IS NULL))
) STRICT;

CREATE TABLE "r_assessment_selection" (
  __row_id INTEGER PRIMARY KEY,
  "proposal__state" INTEGER NOT NULL CHECK("proposal__state" IN (2)),
  "proposal" INTEGER REFERENCES "r_assessment_selection_proposal"(__row_id),
  "generation__state" INTEGER NOT NULL CHECK("generation__state" IN (2)),
  "generation" TEXT,
  "selected__state" INTEGER NOT NULL CHECK("selected__state" IN (1,2)),
  "selected" INTEGER REFERENCES "r_assessment_selection_selected"(__row_id),
  CHECK(("proposal__state"=2 AND "proposal" IS NOT NULL) OR ("proposal__state" IN (0,1) AND "proposal" IS NULL)),
  CHECK(("generation__state"=2 AND "generation" IS NOT NULL) OR ("generation__state" IN (0,1) AND "generation" IS NULL)),
  CHECK(("selected__state"=2 AND "selected" IS NOT NULL) OR ("selected__state" IN (0,1) AND "selected" IS NULL))
) STRICT;

CREATE TABLE "r_assessment_selection_proposal" (
  __row_id INTEGER PRIMARY KEY,
  "proposal_id__state" INTEGER NOT NULL CHECK("proposal_id__state" IN (2)),
  "proposal_id" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  CHECK(("proposal_id__state"=2 AND "proposal_id" IS NOT NULL) OR ("proposal_id__state" IN (0,1) AND "proposal_id" IS NULL)),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL)),
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL))
) STRICT;

CREATE TABLE "r_assessment_selection_selected" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_assessment_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_validation_capture_latest_proposal_key" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_validation_capture_authority_sequence" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_stored_operation" (
  __row_id INTEGER PRIMARY KEY,
  "owner__state" INTEGER NOT NULL CHECK("owner__state" IN (2)),
  "owner" TEXT,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  "status__state" INTEGER NOT NULL CHECK("status__state" IN (2)),
  "status" INTEGER REFERENCES "r_operation_status_internal"(__row_id),
  "input__state" INTEGER NOT NULL CHECK("input__state" IN (1,2)),
  "input" INTEGER REFERENCES "r_stored_operation_input"(__row_id),
  "footprint__state" INTEGER NOT NULL CHECK("footprint__state" IN (2)),
  "footprint" INTEGER REFERENCES "r_footprint"(__row_id),
  "validation_capture__state" INTEGER NOT NULL CHECK("validation_capture__state" IN (0,1,2)),
  "validation_capture" INTEGER REFERENCES "r_stored_operation_validation_capture"(__row_id),
  CHECK(("owner__state"=2 AND "owner" IS NOT NULL) OR ("owner__state" IN (0,1) AND "owner" IS NULL)),
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL)),
  CHECK(("status__state"=2 AND "status" IS NOT NULL) OR ("status__state" IN (0,1) AND "status" IS NULL)),
  CHECK(("input__state"=2 AND "input" IS NOT NULL) OR ("input__state" IN (0,1) AND "input" IS NULL)),
  CHECK(("footprint__state"=2 AND "footprint" IS NOT NULL) OR ("footprint__state" IN (0,1) AND "footprint" IS NULL)),
  CHECK(("validation_capture__state"=2 AND "validation_capture" IS NOT NULL) OR ("validation_capture__state" IN (0,1) AND "validation_capture" IS NULL))
) STRICT;

CREATE TABLE "r_operation_status_internal" (
  __row_id INTEGER PRIMARY KEY,
  "validation__state" INTEGER NOT NULL CHECK("validation__state" IN (0,1,2)),
  "validation" INTEGER REFERENCES "r_operation_status_internal_validation"(__row_id),
  "failure__state" INTEGER NOT NULL CHECK("failure__state" IN (0,1,2)),
  "failure" INTEGER REFERENCES "r_operation_status_internal_failure"(__row_id),
  "operation_id__state" INTEGER NOT NULL CHECK("operation_id__state" IN (2)),
  "operation_id" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  "state__state" INTEGER NOT NULL CHECK("state__state" IN (2)),
  "state" TEXT,
  "proposal__state" INTEGER NOT NULL CHECK("proposal__state" IN (1,2)),
  "proposal" INTEGER REFERENCES "r_operation_status_internal_proposal"(__row_id),
  "receipt__state" INTEGER NOT NULL CHECK("receipt__state" IN (1,2)),
  "receipt" INTEGER REFERENCES "r_operation_status_internal_receipt"(__row_id),
  "cancellation_requested__state" INTEGER NOT NULL CHECK("cancellation_requested__state" IN (2)),
  "cancellation_requested" INTEGER,
  CHECK(("validation__state"=2 AND "validation" IS NOT NULL) OR ("validation__state" IN (0,1) AND "validation" IS NULL)),
  CHECK(("failure__state"=2 AND "failure" IS NOT NULL) OR ("failure__state" IN (0,1) AND "failure" IS NULL)),
  CHECK(("operation_id__state"=2 AND "operation_id" IS NOT NULL) OR ("operation_id__state" IN (0,1) AND "operation_id" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind" IN ('propose','validate','commit','cancel')),
  CHECK(("state__state"=2 AND "state" IS NOT NULL) OR ("state__state" IN (0,1) AND "state" IS NULL)),
  CHECK("state" IN ('queued','running','awaiting_authority','committing','succeeded','failed','cancelled','interrupted')),
  CHECK(("proposal__state"=2 AND "proposal" IS NOT NULL) OR ("proposal__state" IN (0,1) AND "proposal" IS NULL)),
  CHECK(("receipt__state"=2 AND "receipt" IS NOT NULL) OR ("receipt__state" IN (0,1) AND "receipt" IS NULL)),
  CHECK(("cancellation_requested__state"=2 AND "cancellation_requested" IS NOT NULL) OR ("cancellation_requested__state" IN (0,1) AND "cancellation_requested" IS NULL)),
  CHECK("cancellation_requested" IN (0,1))
) STRICT;

CREATE TABLE "r_operation_status_internal_validation" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_validation"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_operation_status_internal_failure" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 TEXT,
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_operation_status_internal_proposal" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_proposal"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_operation_status_internal_receipt" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_commit_receipt"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_commit_receipt" (
  __row_id INTEGER PRIMARY KEY,
  "operation_id__state" INTEGER NOT NULL CHECK("operation_id__state" IN (2)),
  "operation_id" TEXT,
  "proposal_id__state" INTEGER NOT NULL CHECK("proposal_id__state" IN (2)),
  "proposal_id" TEXT,
  "revision__state" INTEGER NOT NULL CHECK("revision__state" IN (2)),
  "revision" TEXT,
  CHECK(("operation_id__state"=2 AND "operation_id" IS NOT NULL) OR ("operation_id__state" IN (0,1) AND "operation_id" IS NULL)),
  CHECK(("proposal_id__state"=2 AND "proposal_id" IS NOT NULL) OR ("proposal_id__state" IN (0,1) AND "proposal_id" IS NULL)),
  CHECK(("revision__state"=2 AND "revision" IS NOT NULL) OR ("revision__state" IN (0,1) AND "revision" IS NULL))
) STRICT;

CREATE TABLE "r_stored_operation_input" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_commit_input"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_commit_input" (
  __row_id INTEGER PRIMARY KEY,
  "universe__state" INTEGER NOT NULL CHECK("universe__state" IN (2)),
  "universe" TEXT,
  "continuity__state" INTEGER NOT NULL CHECK("continuity__state" IN (2)),
  "continuity" TEXT,
  "expected_head__state" INTEGER NOT NULL CHECK("expected_head__state" IN (2)),
  "expected_head" TEXT,
  "principal__state" INTEGER NOT NULL CHECK("principal__state" IN (2)),
  "principal" TEXT,
  "decision__state" INTEGER NOT NULL CHECK("decision__state" IN (2)),
  "decision" TEXT,
  "reason__state" INTEGER NOT NULL CHECK("reason__state" IN (2)),
  "reason" TEXT,
  "idempotency_key__state" INTEGER NOT NULL CHECK("idempotency_key__state" IN (2)),
  "idempotency_key" TEXT,
  "changes__state" INTEGER NOT NULL CHECK("changes__state" IN (2)),
  "changes" INTEGER REFERENCES "r_commit_input_changes"(__row_id),
  CHECK(("universe__state"=2 AND "universe" IS NOT NULL) OR ("universe__state" IN (0,1) AND "universe" IS NULL)),
  CHECK(("continuity__state"=2 AND "continuity" IS NOT NULL) OR ("continuity__state" IN (0,1) AND "continuity" IS NULL)),
  CHECK(("expected_head__state"=2 AND "expected_head" IS NOT NULL) OR ("expected_head__state" IN (0,1) AND "expected_head" IS NULL)),
  CHECK(("principal__state"=2 AND "principal" IS NOT NULL) OR ("principal__state" IN (0,1) AND "principal" IS NULL)),
  CHECK(("decision__state"=2 AND "decision" IS NOT NULL) OR ("decision__state" IN (0,1) AND "decision" IS NULL)),
  CHECK(("reason__state"=2 AND "reason" IS NOT NULL) OR ("reason__state" IN (0,1) AND "reason" IS NULL)),
  CHECK(("idempotency_key__state"=2 AND "idempotency_key" IS NOT NULL) OR ("idempotency_key__state" IN (0,1) AND "idempotency_key" IS NULL)),
  CHECK(("changes__state"=2 AND "changes" IS NOT NULL) OR ("changes__state" IN (0,1) AND "changes" IS NULL))
) STRICT;

CREATE TABLE "r_commit_input_changes" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_commit_input_changes_items" (owner INTEGER NOT NULL REFERENCES "r_commit_input_changes"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_assignment"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_stored_operation_validation_capture" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_validation_capture"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_approval_evidence" (
  __row_id INTEGER PRIMARY KEY,
  "author__state" INTEGER NOT NULL CHECK("author__state" IN (2)),
  "author" TEXT,
  "proposal__state" INTEGER NOT NULL CHECK("proposal__state" IN (2)),
  "proposal" INTEGER REFERENCES "r_proposal_ref"(__row_id),
  "validation_digest__state" INTEGER NOT NULL CHECK("validation_digest__state" IN (2)),
  "validation_digest" TEXT,
  "evaluator__state" INTEGER NOT NULL CHECK("evaluator__state" IN (2)),
  "evaluator" TEXT,
  CHECK(("author__state"=2 AND "author" IS NOT NULL) OR ("author__state" IN (0,1) AND "author" IS NULL)),
  CHECK(("proposal__state"=2 AND "proposal" IS NOT NULL) OR ("proposal__state" IN (0,1) AND "proposal" IS NULL)),
  CHECK(("validation_digest__state"=2 AND "validation_digest" IS NOT NULL) OR ("validation_digest__state" IN (0,1) AND "validation_digest" IS NULL)),
  CHECK(("evaluator__state"=2 AND "evaluator" IS NOT NULL) OR ("evaluator__state" IN (0,1) AND "evaluator" IS NULL))
) STRICT;

CREATE TABLE "r_assessment_envelope" (
  __row_id INTEGER PRIMARY KEY,
  "assessment_id__state" INTEGER NOT NULL CHECK("assessment_id__state" IN (2)),
  "assessment_id" TEXT,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  "body__state" INTEGER NOT NULL CHECK("body__state" IN (2)),
  "body" INTEGER REFERENCES "r_source_assessment"(__row_id),
  CHECK(("assessment_id__state"=2 AND "assessment_id" IS NOT NULL) OR ("assessment_id__state" IN (0,1) AND "assessment_id" IS NULL)),
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL)),
  CHECK(("body__state"=2 AND "body" IS NOT NULL) OR ("body__state" IN (0,1) AND "body" IS NULL))
) STRICT;

CREATE TABLE "r_source_assessment" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  "proposal__state" INTEGER NOT NULL CHECK("proposal__state" IN (2)),
  "proposal" INTEGER REFERENCES "r_source_assessment_proposal"(__row_id),
  "base_frame__state" INTEGER NOT NULL CHECK("base_frame__state" IN (2)),
  "base_frame" INTEGER REFERENCES "r_frame"(__row_id),
  "assessor__state" INTEGER NOT NULL CHECK("assessor__state" IN (2)),
  "assessor" INTEGER REFERENCES "r_assessor"(__row_id),
  "sources__state" INTEGER NOT NULL CHECK("sources__state" IN (2)),
  "sources" INTEGER REFERENCES "r_source_assessment_sources"(__row_id),
  "dependencies__state" INTEGER NOT NULL CHECK("dependencies__state" IN (2)),
  "dependencies" INTEGER REFERENCES "r_source_assessment_dependencies"(__row_id),
  "declared_inventory__state" INTEGER NOT NULL CHECK("declared_inventory__state" IN (2)),
  "declared_inventory" INTEGER REFERENCES "r_source_assessment_declared_inventory"(__row_id),
  "inventory_declaration__state" INTEGER NOT NULL CHECK("inventory_declaration__state" IN (2)),
  "inventory_declaration" INTEGER REFERENCES "r_inventory_declaration"(__row_id),
  "claim_mappings__state" INTEGER NOT NULL CHECK("claim_mappings__state" IN (2)),
  "claim_mappings" INTEGER REFERENCES "r_source_assessment_claim_mappings"(__row_id),
  "unresolved__state" INTEGER NOT NULL CHECK("unresolved__state" IN (2)),
  "unresolved" INTEGER REFERENCES "r_source_assessment_unresolved"(__row_id),
  "conclusion__state" INTEGER NOT NULL CHECK("conclusion__state" IN (2)),
  "conclusion" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind" IN ('source_assessment')),
  CHECK(("proposal__state"=2 AND "proposal" IS NOT NULL) OR ("proposal__state" IN (0,1) AND "proposal" IS NULL)),
  CHECK(("base_frame__state"=2 AND "base_frame" IS NOT NULL) OR ("base_frame__state" IN (0,1) AND "base_frame" IS NULL)),
  CHECK(("assessor__state"=2 AND "assessor" IS NOT NULL) OR ("assessor__state" IN (0,1) AND "assessor" IS NULL)),
  CHECK(("sources__state"=2 AND "sources" IS NOT NULL) OR ("sources__state" IN (0,1) AND "sources" IS NULL)),
  CHECK(("dependencies__state"=2 AND "dependencies" IS NOT NULL) OR ("dependencies__state" IN (0,1) AND "dependencies" IS NULL)),
  CHECK(("declared_inventory__state"=2 AND "declared_inventory" IS NOT NULL) OR ("declared_inventory__state" IN (0,1) AND "declared_inventory" IS NULL)),
  CHECK(("inventory_declaration__state"=2 AND "inventory_declaration" IS NOT NULL) OR ("inventory_declaration__state" IN (0,1) AND "inventory_declaration" IS NULL)),
  CHECK(("claim_mappings__state"=2 AND "claim_mappings" IS NOT NULL) OR ("claim_mappings__state" IN (0,1) AND "claim_mappings" IS NULL)),
  CHECK(("unresolved__state"=2 AND "unresolved" IS NOT NULL) OR ("unresolved__state" IN (0,1) AND "unresolved" IS NULL)),
  CHECK(("conclusion__state"=2 AND "conclusion" IS NOT NULL) OR ("conclusion__state" IN (0,1) AND "conclusion" IS NULL)),
  CHECK("conclusion" IN ('consistent_with_declared_inventory','inconsistent','unresolved'))
) STRICT;

CREATE TABLE "r_source_assessment_proposal" (
  __row_id INTEGER PRIMARY KEY,
  "proposal_id__state" INTEGER NOT NULL CHECK("proposal_id__state" IN (2)),
  "proposal_id" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  CHECK(("proposal_id__state"=2 AND "proposal_id" IS NOT NULL) OR ("proposal_id__state" IN (0,1) AND "proposal_id" IS NULL)),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL)),
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL))
) STRICT;

CREATE TABLE "r_assessor" (
  __row_id INTEGER PRIMARY KEY,
  "principal__state" INTEGER NOT NULL CHECK("principal__state" IN (2)),
  "principal" TEXT,
  "method__state" INTEGER NOT NULL CHECK("method__state" IN (2)),
  "method" TEXT,
  "tool__state" INTEGER NOT NULL CHECK("tool__state" IN (1,2)),
  "tool" INTEGER REFERENCES "r_assessor_tool"(__row_id),
  "assessed_at__state" INTEGER NOT NULL CHECK("assessed_at__state" IN (2)),
  "assessed_at" TEXT,
  CHECK(("principal__state"=2 AND "principal" IS NOT NULL) OR ("principal__state" IN (0,1) AND "principal" IS NULL)),
  CHECK(("method__state"=2 AND "method" IS NOT NULL) OR ("method__state" IN (0,1) AND "method" IS NULL)),
  CHECK("method" IN ('human_review','external_model_review')),
  CHECK(("tool__state"=2 AND "tool" IS NOT NULL) OR ("tool__state" IN (0,1) AND "tool" IS NULL)),
  CHECK(("assessed_at__state"=2 AND "assessed_at" IS NOT NULL) OR ("assessed_at__state" IN (0,1) AND "assessed_at" IS NULL))
) STRICT;

CREATE TABLE "r_assessor_tool" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_tool_identity"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_tool_identity" (
  __row_id INTEGER PRIMARY KEY,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  "model_revision__state" INTEGER NOT NULL CHECK("model_revision__state" IN (2)),
  "model_revision" TEXT,
  "procedure_digest__state" INTEGER NOT NULL CHECK("procedure_digest__state" IN (2)),
  "procedure_digest" TEXT,
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL)),
  CHECK(("model_revision__state"=2 AND "model_revision" IS NOT NULL) OR ("model_revision__state" IN (0,1) AND "model_revision" IS NULL)),
  CHECK(("procedure_digest__state"=2 AND "procedure_digest" IS NOT NULL) OR ("procedure_digest__state" IN (0,1) AND "procedure_digest" IS NULL))
) STRICT;

CREATE TABLE "r_source_assessment_sources" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_source_assessment_sources_items" (owner INTEGER NOT NULL REFERENCES "r_source_assessment_sources"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_source_binding"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_source_assessment_dependencies" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_source_assessment_dependencies_items" (owner INTEGER NOT NULL REFERENCES "r_source_assessment_dependencies"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_assessment_version_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_source_assessment_declared_inventory" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_source_assessment_declared_inventory_items" (owner INTEGER NOT NULL REFERENCES "r_source_assessment_declared_inventory"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_material_item"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_material_item" (
  __row_id INTEGER PRIMARY KEY,
  "item_id__state" INTEGER NOT NULL CHECK("item_id__state" IN (2)),
  "item_id" TEXT,
  "source_key__state" INTEGER NOT NULL CHECK("source_key__state" IN (2)),
  "source_key" TEXT,
  "range__state" INTEGER NOT NULL CHECK("range__state" IN (2)),
  "range" INTEGER REFERENCES "r_byte_range"(__row_id),
  "material_kind__state" INTEGER NOT NULL CHECK("material_kind__state" IN (2)),
  "material_kind" TEXT,
  "statement__state" INTEGER NOT NULL CHECK("statement__state" IN (2)),
  "statement" TEXT,
  "mapping_ids__state" INTEGER NOT NULL CHECK("mapping_ids__state" IN (2)),
  "mapping_ids" INTEGER REFERENCES "r_material_item_mapping_ids"(__row_id),
  "unresolved_ids__state" INTEGER NOT NULL CHECK("unresolved_ids__state" IN (2)),
  "unresolved_ids" INTEGER REFERENCES "r_material_item_unresolved_ids"(__row_id),
  CHECK(("item_id__state"=2 AND "item_id" IS NOT NULL) OR ("item_id__state" IN (0,1) AND "item_id" IS NULL)),
  CHECK(("source_key__state"=2 AND "source_key" IS NOT NULL) OR ("source_key__state" IN (0,1) AND "source_key" IS NULL)),
  CHECK(("range__state"=2 AND "range" IS NOT NULL) OR ("range__state" IN (0,1) AND "range" IS NULL)),
  CHECK(("material_kind__state"=2 AND "material_kind" IS NOT NULL) OR ("material_kind__state" IN (0,1) AND "material_kind" IS NULL)),
  CHECK("material_kind" IN ('fact','action','prerequisite','effect','knowledge','description','disclosure','unchanged_state')),
  CHECK(("statement__state"=2 AND "statement" IS NOT NULL) OR ("statement__state" IN (0,1) AND "statement" IS NULL)),
  CHECK(("mapping_ids__state"=2 AND "mapping_ids" IS NOT NULL) OR ("mapping_ids__state" IN (0,1) AND "mapping_ids" IS NULL)),
  CHECK(("unresolved_ids__state"=2 AND "unresolved_ids" IS NOT NULL) OR ("unresolved_ids__state" IN (0,1) AND "unresolved_ids" IS NULL))
) STRICT;

CREATE TABLE "r_material_item_mapping_ids" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_material_item_mapping_ids_items" (owner INTEGER NOT NULL REFERENCES "r_material_item_mapping_ids"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_material_item_unresolved_ids" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_material_item_unresolved_ids_items" (owner INTEGER NOT NULL REFERENCES "r_material_item_unresolved_ids"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_inventory_declaration" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "exclusions__state" INTEGER NOT NULL CHECK("exclusions__state" IN (2)),
  "exclusions" INTEGER REFERENCES "r_inventory_declaration_exclusions"(__row_id),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind" IN ('material_inventory_declared','no_material_claims')),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("exclusions__state"=2 AND "exclusions" IS NOT NULL) OR ("exclusions__state" IN (0,1) AND "exclusions" IS NULL))
) STRICT;

CREATE TABLE "r_inventory_declaration_exclusions" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_inventory_declaration_exclusions_items" (owner INTEGER NOT NULL REFERENCES "r_inventory_declaration_exclusions"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_exclusion"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_exclusion" (
  __row_id INTEGER PRIMARY KEY,
  "source_key__state" INTEGER NOT NULL CHECK("source_key__state" IN (2)),
  "source_key" TEXT,
  "range__state" INTEGER NOT NULL CHECK("range__state" IN (2)),
  "range" INTEGER REFERENCES "r_byte_range"(__row_id),
  "reason__state" INTEGER NOT NULL CHECK("reason__state" IN (2)),
  "reason" TEXT,
  CHECK(("source_key__state"=2 AND "source_key" IS NOT NULL) OR ("source_key__state" IN (0,1) AND "source_key" IS NULL)),
  CHECK(("range__state"=2 AND "range" IS NOT NULL) OR ("range__state" IN (0,1) AND "range" IS NULL)),
  CHECK(("reason__state"=2 AND "reason" IS NOT NULL) OR ("reason__state" IN (0,1) AND "reason" IS NULL))
) STRICT;

CREATE TABLE "r_source_assessment_claim_mappings" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_source_assessment_claim_mappings_items" (owner INTEGER NOT NULL REFERENCES "r_source_assessment_claim_mappings"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_claim_mapping"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_claim_mapping" (
  __row_id INTEGER PRIMARY KEY,
  "mapping_id__state" INTEGER NOT NULL CHECK("mapping_id__state" IN (2)),
  "mapping_id" TEXT,
  "item_ids__state" INTEGER NOT NULL CHECK("item_ids__state" IN (2)),
  "item_ids" INTEGER REFERENCES "r_claim_mapping_item_ids"(__row_id),
  "referents__state" INTEGER NOT NULL CHECK("referents__state" IN (2)),
  "referents" INTEGER REFERENCES "r_claim_mapping_referents"(__row_id),
  "context__state" INTEGER NOT NULL CHECK("context__state" IN (2)),
  "context" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  "world__state" INTEGER NOT NULL CHECK("world__state" IN (1,2)),
  "world" INTEGER REFERENCES "r_claim_mapping_world"(__row_id),
  "realm__state" INTEGER NOT NULL CHECK("realm__state" IN (1,2)),
  "realm" INTEGER REFERENCES "r_claim_mapping_realm"(__row_id),
  "story_time__state" INTEGER NOT NULL CHECK("story_time__state" IN (2)),
  "story_time" INTEGER REFERENCES "r_temporal_expression"(__row_id),
  "narration_position__state" INTEGER NOT NULL CHECK("narration_position__state" IN (2)),
  "narration_position" INTEGER REFERENCES "r_position"(__row_id),
  "reader_position__state" INTEGER NOT NULL CHECK("reader_position__state" IN (2)),
  "reader_position" INTEGER REFERENCES "r_position"(__row_id),
  "occurrence__state" INTEGER NOT NULL CHECK("occurrence__state" IN (2)),
  "occurrence" TEXT,
  "modality__state" INTEGER NOT NULL CHECK("modality__state" IN (2)),
  "modality" TEXT,
  "semantic__state" INTEGER NOT NULL CHECK("semantic__state" IN (2)),
  "semantic" INTEGER REFERENCES "r_semantic_mapping"(__row_id),
  "candidate_links__state" INTEGER NOT NULL CHECK("candidate_links__state" IN (2)),
  "candidate_links" INTEGER REFERENCES "r_claim_mapping_candidate_links"(__row_id),
  "judgment__state" INTEGER NOT NULL CHECK("judgment__state" IN (2)),
  "judgment" TEXT,
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  CHECK(("mapping_id__state"=2 AND "mapping_id" IS NOT NULL) OR ("mapping_id__state" IN (0,1) AND "mapping_id" IS NULL)),
  CHECK(("item_ids__state"=2 AND "item_ids" IS NOT NULL) OR ("item_ids__state" IN (0,1) AND "item_ids" IS NULL)),
  CHECK(("referents__state"=2 AND "referents" IS NOT NULL) OR ("referents__state" IN (0,1) AND "referents" IS NULL)),
  CHECK(("context__state"=2 AND "context" IS NOT NULL) OR ("context__state" IN (0,1) AND "context" IS NULL)),
  CHECK(("world__state"=2 AND "world" IS NOT NULL) OR ("world__state" IN (0,1) AND "world" IS NULL)),
  CHECK(("realm__state"=2 AND "realm" IS NOT NULL) OR ("realm__state" IN (0,1) AND "realm" IS NULL)),
  CHECK(("story_time__state"=2 AND "story_time" IS NOT NULL) OR ("story_time__state" IN (0,1) AND "story_time" IS NULL)),
  CHECK(("narration_position__state"=2 AND "narration_position" IS NOT NULL) OR ("narration_position__state" IN (0,1) AND "narration_position" IS NULL)),
  CHECK(("reader_position__state"=2 AND "reader_position" IS NOT NULL) OR ("reader_position__state" IN (0,1) AND "reader_position" IS NULL)),
  CHECK(("occurrence__state"=2 AND "occurrence" IS NOT NULL) OR ("occurrence__state" IN (0,1) AND "occurrence" IS NULL)),
  CHECK("occurrence" IN ('occurred','planned','hypothetical','reported','unknown')),
  CHECK(("modality__state"=2 AND "modality" IS NOT NULL) OR ("modality__state" IN (0,1) AND "modality" IS NULL)),
  CHECK("modality" IN ('asserted','negated','possible','counterfactual','attributed','unknown')),
  CHECK(("semantic__state"=2 AND "semantic" IS NOT NULL) OR ("semantic__state" IN (0,1) AND "semantic" IS NULL)),
  CHECK(("candidate_links__state"=2 AND "candidate_links" IS NOT NULL) OR ("candidate_links__state" IN (0,1) AND "candidate_links" IS NULL)),
  CHECK(("judgment__state"=2 AND "judgment" IS NOT NULL) OR ("judgment__state" IN (0,1) AND "judgment" IS NULL)),
  CHECK("judgment" IN ('supported','contradicted','unresolved')),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL))
) STRICT;

CREATE TABLE "r_claim_mapping_item_ids" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_claim_mapping_item_ids_items" (owner INTEGER NOT NULL REFERENCES "r_claim_mapping_item_ids"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_claim_mapping_referents" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_claim_mapping_referents_items" (owner INTEGER NOT NULL REFERENCES "r_claim_mapping_referents"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_assessment_version_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_claim_mapping_world" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_claim_mapping_realm" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_position" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 2),
  v0 INTEGER REFERENCES "r_position_v0"(__row_id),
  v1 INTEGER REFERENCES "r_position_v1"(__row_id),
  v2 INTEGER REFERENCES "r_position_v2"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL)
) STRICT;

CREATE TABLE "r_position_v0" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='not_applicable')
) STRICT;

CREATE TABLE "r_position_v1" (
  __row_id INTEGER PRIMARY KEY,
  "reason__state" INTEGER NOT NULL CHECK("reason__state" IN (2)),
  "reason" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("reason__state"=2 AND "reason" IS NOT NULL) OR ("reason__state" IN (0,1) AND "reason" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='unknown')
) STRICT;

CREATE TABLE "r_position_v2" (
  __row_id INTEGER PRIMARY KEY,
  "work_edition__state" INTEGER NOT NULL CHECK("work_edition__state" IN (2)),
  "work_edition" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  "scene_id__state" INTEGER NOT NULL CHECK("scene_id__state" IN (2)),
  "scene_id" TEXT,
  "ordinal__state" INTEGER NOT NULL CHECK("ordinal__state" IN (2)),
  "ordinal" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("work_edition__state"=2 AND "work_edition" IS NOT NULL) OR ("work_edition__state" IN (0,1) AND "work_edition" IS NULL)),
  CHECK(("scene_id__state"=2 AND "scene_id" IS NOT NULL) OR ("scene_id__state" IN (0,1) AND "scene_id" IS NULL)),
  CHECK(("ordinal__state"=2 AND "ordinal" IS NOT NULL) OR ("ordinal__state" IN (0,1) AND "ordinal" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='work_position')
) STRICT;

CREATE TABLE "r_semantic_mapping" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 3),
  v0 INTEGER REFERENCES "r_semantic_mapping_v0"(__row_id),
  v1 INTEGER REFERENCES "r_semantic_mapping_v1"(__row_id),
  v2 INTEGER REFERENCES "r_semantic_mapping_v2"(__row_id),
  v3 INTEGER REFERENCES "r_semantic_mapping_v3"(__row_id),
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL),
  CHECK(variant!=1 OR v1 IS NOT NULL),
  CHECK(variant=2 OR v2 IS NULL),
  CHECK(variant!=2 OR v2 IS NOT NULL),
  CHECK(variant=3 OR v3 IS NULL),
  CHECK(variant!=3 OR v3 IS NOT NULL)
) STRICT;

CREATE TABLE "r_semantic_mapping_v0" (
  __row_id INTEGER PRIMARY KEY,
  "predicate__state" INTEGER NOT NULL CHECK("predicate__state" IN (2)),
  "predicate" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  "value__state" INTEGER NOT NULL CHECK("value__state" IN (2)),
  "value" INTEGER REFERENCES "r_value"(__row_id),
  "roles__state" INTEGER NOT NULL CHECK("roles__state" IN (2)),
  "roles" INTEGER REFERENCES "r_semantic_mapping_v0_roles"(__row_id),
  "polarity__state" INTEGER NOT NULL CHECK("polarity__state" IN (2)),
  "polarity" TEXT,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("predicate__state"=2 AND "predicate" IS NOT NULL) OR ("predicate__state" IN (0,1) AND "predicate" IS NULL)),
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("value__state"=2 AND "value" IS NOT NULL) OR ("value__state" IN (0,1) AND "value" IS NULL)),
  CHECK(("roles__state"=2 AND "roles" IS NOT NULL) OR ("roles__state" IN (0,1) AND "roles" IS NULL)),
  CHECK(("polarity__state"=2 AND "polarity" IS NOT NULL) OR ("polarity__state" IN (0,1) AND "polarity" IS NULL)),
  CHECK("polarity" IN ('support','refutation')),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='claim')
) STRICT;

CREATE TABLE "r_semantic_mapping_v0_roles" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_semantic_mapping_v0_roles_items" (owner INTEGER NOT NULL REFERENCES "r_semantic_mapping_v0_roles"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_role_participant"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_role_participant" (
  __row_id INTEGER PRIMARY KEY,
  "role__state" INTEGER NOT NULL CHECK("role__state" IN (2)),
  "role" TEXT,
  "participant__state" INTEGER NOT NULL CHECK("participant__state" IN (2)),
  "participant" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  CHECK(("role__state"=2 AND "role" IS NOT NULL) OR ("role__state" IN (0,1) AND "role" IS NULL)),
  CHECK(("participant__state"=2 AND "participant" IS NOT NULL) OR ("participant__state" IN (0,1) AND "participant" IS NULL))
) STRICT;

CREATE TABLE "r_semantic_mapping_v1" (
  __row_id INTEGER PRIMARY KEY,
  "action__state" INTEGER NOT NULL CHECK("action__state" IN (2)),
  "action" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  "participants__state" INTEGER NOT NULL CHECK("participants__state" IN (2)),
  "participants" INTEGER REFERENCES "r_semantic_mapping_v1_participants"(__row_id),
  "prerequisites__state" INTEGER NOT NULL CHECK("prerequisites__state" IN (2)),
  "prerequisites" INTEGER REFERENCES "r_semantic_mapping_v1_prerequisites"(__row_id),
  "effects__state" INTEGER NOT NULL CHECK("effects__state" IN (2)),
  "effects" INTEGER REFERENCES "r_semantic_mapping_v1_effects"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("action__state"=2 AND "action" IS NOT NULL) OR ("action__state" IN (0,1) AND "action" IS NULL)),
  CHECK(("participants__state"=2 AND "participants" IS NOT NULL) OR ("participants__state" IN (0,1) AND "participants" IS NULL)),
  CHECK(("prerequisites__state"=2 AND "prerequisites" IS NOT NULL) OR ("prerequisites__state" IN (0,1) AND "prerequisites" IS NULL)),
  CHECK(("effects__state"=2 AND "effects" IS NOT NULL) OR ("effects__state" IN (0,1) AND "effects" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='action')
) STRICT;

CREATE TABLE "r_semantic_mapping_v1_participants" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_semantic_mapping_v1_participants_items" (owner INTEGER NOT NULL REFERENCES "r_semantic_mapping_v1_participants"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_role_participant"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_semantic_mapping_v1_prerequisites" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_semantic_mapping_v1_prerequisites_items" (owner INTEGER NOT NULL REFERENCES "r_semantic_mapping_v1_prerequisites"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_assessment_version_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_semantic_mapping_v1_effects" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_semantic_mapping_v1_effects_items" (owner INTEGER NOT NULL REFERENCES "r_semantic_mapping_v1_effects"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_assessment_version_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_semantic_mapping_v2" (
  __row_id INTEGER PRIMARY KEY,
  "holder__state" INTEGER NOT NULL CHECK("holder__state" IN (2)),
  "holder" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  "content__state" INTEGER NOT NULL CHECK("content__state" IN (2)),
  "content" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  "acquisition__state" INTEGER NOT NULL CHECK("acquisition__state" IN (2)),
  "acquisition" INTEGER REFERENCES "r_semantic_mapping_v2_acquisition"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("holder__state"=2 AND "holder" IS NOT NULL) OR ("holder__state" IN (0,1) AND "holder" IS NULL)),
  CHECK(("content__state"=2 AND "content" IS NOT NULL) OR ("content__state" IN (0,1) AND "content" IS NULL)),
  CHECK(("acquisition__state"=2 AND "acquisition" IS NOT NULL) OR ("acquisition__state" IN (0,1) AND "acquisition" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='knowledge')
) STRICT;

CREATE TABLE "r_semantic_mapping_v2_acquisition" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_semantic_mapping_v2_acquisition_items" (owner INTEGER NOT NULL REFERENCES "r_semantic_mapping_v2_acquisition"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_assessment_version_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_semantic_mapping_v3" (
  __row_id INTEGER PRIMARY KEY,
  "subject__state" INTEGER NOT NULL CHECK("subject__state" IN (2)),
  "subject" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  "depiction__state" INTEGER NOT NULL CHECK("depiction__state" IN (2)),
  "depiction" TEXT,
  "implied_claims__state" INTEGER NOT NULL CHECK("implied_claims__state" IN (2)),
  "implied_claims" INTEGER REFERENCES "r_semantic_mapping_v3_implied_claims"(__row_id),
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  CHECK(("subject__state"=2 AND "subject" IS NOT NULL) OR ("subject__state" IN (0,1) AND "subject" IS NULL)),
  CHECK(("depiction__state"=2 AND "depiction" IS NOT NULL) OR ("depiction__state" IN (0,1) AND "depiction" IS NULL)),
  CHECK("depiction" IN ('factual','subjective','inspiration')),
  CHECK(("implied_claims__state"=2 AND "implied_claims" IS NOT NULL) OR ("implied_claims__state" IN (0,1) AND "implied_claims" IS NULL)),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind"='source_description')
) STRICT;

CREATE TABLE "r_semantic_mapping_v3_implied_claims" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_semantic_mapping_v3_implied_claims_items" (owner INTEGER NOT NULL REFERENCES "r_semantic_mapping_v3_implied_claims"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_assessment_version_ref"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_claim_mapping_candidate_links" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_claim_mapping_candidate_links_items" (owner INTEGER NOT NULL REFERENCES "r_claim_mapping_candidate_links"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_candidate_link"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_candidate_link" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" INTEGER REFERENCES "r_assessment_version_ref"(__row_id),
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind" IN ('proposed_record','unchanged_record','historical_evidence')),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL))
) STRICT;

CREATE TABLE "r_source_assessment_unresolved" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_source_assessment_unresolved_items" (owner INTEGER NOT NULL REFERENCES "r_source_assessment_unresolved"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_unresolved_disposition"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_unresolved_disposition" (
  __row_id INTEGER PRIMARY KEY,
  "unresolved_id__state" INTEGER NOT NULL CHECK("unresolved_id__state" IN (2)),
  "unresolved_id" TEXT,
  "item_ids__state" INTEGER NOT NULL CHECK("item_ids__state" IN (2)),
  "item_ids" INTEGER REFERENCES "r_unresolved_disposition_item_ids"(__row_id),
  "reason__state" INTEGER NOT NULL CHECK("reason__state" IN (2)),
  "reason" TEXT,
  "detail__state" INTEGER NOT NULL CHECK("detail__state" IN (2)),
  "detail" TEXT,
  CHECK(("unresolved_id__state"=2 AND "unresolved_id" IS NOT NULL) OR ("unresolved_id__state" IN (0,1) AND "unresolved_id" IS NULL)),
  CHECK(("item_ids__state"=2 AND "item_ids" IS NOT NULL) OR ("item_ids__state" IN (0,1) AND "item_ids" IS NULL)),
  CHECK(("reason__state"=2 AND "reason" IS NOT NULL) OR ("reason__state" IN (0,1) AND "reason" IS NULL)),
  CHECK("reason" IN ('ambiguous_referent','ambiguous_modality','unsupported_semantics','missing_evidence','unrepresented_material','interpretation_disagreement')),
  CHECK(("detail__state"=2 AND "detail" IS NOT NULL) OR ("detail__state" IN (0,1) AND "detail" IS NULL))
) STRICT;

CREATE TABLE "r_unresolved_disposition_item_ids" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_unresolved_disposition_item_ids_items" (owner INTEGER NOT NULL REFERENCES "r_unresolved_disposition_item_ids"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT, PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_assessment_receipt" (
  __row_id INTEGER PRIMARY KEY,
  "request_digest__state" INTEGER NOT NULL CHECK("request_digest__state" IN (2)),
  "request_digest" TEXT,
  "selection__state" INTEGER NOT NULL CHECK("selection__state" IN (2)),
  "selection" INTEGER REFERENCES "r_assessment_selection"(__row_id),
  "envelope__state" INTEGER NOT NULL CHECK("envelope__state" IN (1,2)),
  "envelope" INTEGER REFERENCES "r_assessment_receipt_envelope"(__row_id),
  CHECK(("request_digest__state"=2 AND "request_digest" IS NOT NULL) OR ("request_digest__state" IN (0,1) AND "request_digest" IS NULL)),
  CHECK(("selection__state"=2 AND "selection" IS NOT NULL) OR ("selection__state" IN (0,1) AND "selection" IS NULL)),
  CHECK(("envelope__state"=2 AND "envelope" IS NOT NULL) OR ("envelope__state" IN (0,1) AND "envelope" IS NULL))
) STRICT;

CREATE TABLE "r_assessment_receipt_envelope" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_assessment_envelope"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_cursor" (
  __row_id INTEGER PRIMARY KEY,
  "binding__state" INTEGER NOT NULL CHECK("binding__state" IN (2)),
  "binding" TEXT,
  "offset__state" INTEGER NOT NULL CHECK("offset__state" IN (2)),
  "offset" TEXT,
  CHECK(("binding__state"=2 AND "binding" IS NOT NULL) OR ("binding__state" IN (0,1) AND "binding" IS NULL)),
  CHECK(("offset__state"=2 AND "offset" IS NOT NULL) OR ("offset__state" IN (0,1) AND "offset" IS NULL))
) STRICT;

CREATE TABLE "r_cancellation" (
  __row_id INTEGER PRIMARY KEY,
  "owner__state" INTEGER NOT NULL CHECK("owner__state" IN (0,2)),
  "owner" TEXT,
  "cancelled__state" INTEGER NOT NULL CHECK("cancelled__state" IN (2)),
  "cancelled" INTEGER,
  CHECK(("owner__state"=2 AND "owner" IS NOT NULL) OR ("owner__state" IN (0,1) AND "owner" IS NULL)),
  CHECK(("cancelled__state"=2 AND "cancelled" IS NOT NULL) OR ("cancelled__state" IN (0,1) AND "cancelled" IS NULL)),
  CHECK("cancelled" IN (0,1))
) STRICT;

CREATE TABLE "r_reserved_record" (
  __row_id INTEGER PRIMARY KEY,
  "proposal_id__state" INTEGER NOT NULL CHECK("proposal_id__state" IN (2)),
  "proposal_id" TEXT,
  CHECK(("proposal_id__state"=2 AND "proposal_id" IS NOT NULL) OR ("proposal_id__state" IN (0,1) AND "proposal_id" IS NULL))
) STRICT;

CREATE TABLE "r_saved_draft" (
  __row_id INTEGER PRIMARY KEY,
  "version__state" INTEGER NOT NULL CHECK("version__state" IN (2)),
  "version" TEXT,
  "content__state" INTEGER NOT NULL CHECK("content__state" IN (2)),
  "content" INTEGER REFERENCES "r_draft_content"(__row_id),
  CHECK(("version__state"=2 AND "version" IS NOT NULL) OR ("version__state" IN (0,1) AND "version" IS NULL)),
  CHECK(("content__state"=2 AND "content" IS NOT NULL) OR ("content__state" IN (0,1) AND "content" IS NULL))
) STRICT;

CREATE TABLE "r_draft_content" (
  __row_id INTEGER PRIMARY KEY,
  "base_revision__state" INTEGER NOT NULL CHECK("base_revision__state" IN (2)),
  "base_revision" TEXT,
  "represented_context__state" INTEGER NOT NULL CHECK("represented_context__state" IN (2)),
  "represented_context" TEXT,
  "operations__state" INTEGER NOT NULL CHECK("operations__state" IN (2)),
  "operations" INTEGER REFERENCES "r_draft_content_operations"(__row_id),
  "rationale__state" INTEGER NOT NULL CHECK("rationale__state" IN (2)),
  "rationale" TEXT,
  "proposal__state" INTEGER NOT NULL CHECK("proposal__state" IN (0,1,2)),
  "proposal" INTEGER REFERENCES "r_draft_content_proposal"(__row_id),
  CHECK(("base_revision__state"=2 AND "base_revision" IS NOT NULL) OR ("base_revision__state" IN (0,1) AND "base_revision" IS NULL)),
  CHECK(("represented_context__state"=2 AND "represented_context" IS NOT NULL) OR ("represented_context__state" IN (0,1) AND "represented_context" IS NULL)),
  CHECK(("operations__state"=2 AND "operations" IS NOT NULL) OR ("operations__state" IN (0,1) AND "operations" IS NULL)),
  CHECK(("rationale__state"=2 AND "rationale" IS NOT NULL) OR ("rationale__state" IN (0,1) AND "rationale" IS NULL)),
  CHECK(("proposal__state"=2 AND "proposal" IS NOT NULL) OR ("proposal__state" IN (0,1) AND "proposal" IS NULL))
) STRICT;

CREATE TABLE "r_draft_content_operations" (
  __row_id INTEGER PRIMARY KEY
) STRICT;

CREATE TABLE "r_draft_content_operations_items" (owner INTEGER NOT NULL REFERENCES "r_draft_content_operations"(__row_id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), item INTEGER REFERENCES "r_domain_operation"(__row_id), PRIMARY KEY(owner,ordinal)) STRICT;

CREATE TABLE "r_draft_content_proposal" (
  __row_id INTEGER PRIMARY KEY,
  variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND 1),
  v0 INTEGER REFERENCES "r_proposal_ref"(__row_id),
  v1 TEXT,
  CHECK(variant=0 OR v0 IS NULL),
  CHECK(variant!=0 OR v0 IS NOT NULL),
  CHECK(variant=1 OR v1 IS NULL)
) STRICT;

CREATE TABLE "r_import_origin" (
  __row_id INTEGER PRIMARY KEY,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  "source_universe__state" INTEGER NOT NULL CHECK("source_universe__state" IN (2)),
  "source_universe" TEXT,
  "target_universe__state" INTEGER NOT NULL CHECK("target_universe__state" IN (2)),
  "target_universe" TEXT,
  "complete__state" INTEGER NOT NULL CHECK("complete__state" IN (2)),
  "complete" INTEGER,
  "omitted_records__state" INTEGER NOT NULL CHECK("omitted_records__state" IN (2)),
  "omitted_records" TEXT,
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL)),
  CHECK(("source_universe__state"=2 AND "source_universe" IS NOT NULL) OR ("source_universe__state" IN (0,1) AND "source_universe" IS NULL)),
  CHECK(("target_universe__state"=2 AND "target_universe" IS NOT NULL) OR ("target_universe__state" IN (0,1) AND "target_universe" IS NULL)),
  CHECK(("complete__state"=2 AND "complete" IS NOT NULL) OR ("complete__state" IN (0,1) AND "complete" IS NULL)),
  CHECK("complete" IN (0,1)),
  CHECK(("omitted_records__state"=2 AND "omitted_records" IS NOT NULL) OR ("omitted_records__state" IN (0,1) AND "omitted_records" IS NULL))
) STRICT;

CREATE TABLE "r_import_admission" (
  __row_id INTEGER PRIMARY KEY,
  "preview_id__state" INTEGER NOT NULL CHECK("preview_id__state" IN (2)),
  "preview_id" TEXT,
  "digest__state" INTEGER NOT NULL CHECK("digest__state" IN (2)),
  "digest" TEXT,
  "universe_id__state" INTEGER NOT NULL CHECK("universe_id__state" IN (2)),
  "universe_id" TEXT,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "complete__state" INTEGER NOT NULL CHECK("complete__state" IN (2)),
  "complete" INTEGER,
  "omitted_records__state" INTEGER NOT NULL CHECK("omitted_records__state" IN (2)),
  "omitted_records" TEXT,
  "imported__state" INTEGER NOT NULL CHECK("imported__state" IN (2)),
  "imported" INTEGER,
  CHECK(("preview_id__state"=2 AND "preview_id" IS NOT NULL) OR ("preview_id__state" IN (0,1) AND "preview_id" IS NULL)),
  CHECK(("digest__state"=2 AND "digest" IS NOT NULL) OR ("digest__state" IN (0,1) AND "digest" IS NULL)),
  CHECK(("universe_id__state"=2 AND "universe_id" IS NOT NULL) OR ("universe_id__state" IN (0,1) AND "universe_id" IS NULL)),
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("complete__state"=2 AND "complete" IS NOT NULL) OR ("complete__state" IN (0,1) AND "complete" IS NULL)),
  CHECK("complete" IN (0,1)),
  CHECK(("omitted_records__state"=2 AND "omitted_records" IS NOT NULL) OR ("omitted_records__state" IN (0,1) AND "omitted_records" IS NULL)),
  CHECK(("imported__state"=2 AND "imported" IS NOT NULL) OR ("imported__state" IN (0,1) AND "imported" IS NULL)),
  CHECK("imported" IN (0,1))
) STRICT;

CREATE TABLE "r_import_preview" (
  __row_id INTEGER PRIMARY KEY,
  "id__state" INTEGER NOT NULL CHECK("id__state" IN (2)),
  "id" TEXT,
  "owner__state" INTEGER NOT NULL CHECK("owner__state" IN (2)),
  "owner" TEXT,
  "source_digest__state" INTEGER NOT NULL CHECK("source_digest__state" IN (2)),
  "source_digest" TEXT,
  "target__state" INTEGER NOT NULL CHECK("target__state" IN (2)),
  "target" TEXT,
  "source__state" INTEGER NOT NULL CHECK("source__state" IN (2)),
  "source" TEXT,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "complete__state" INTEGER NOT NULL CHECK("complete__state" IN (2)),
  "complete" INTEGER,
  "omitted_records__state" INTEGER NOT NULL CHECK("omitted_records__state" IN (2)),
  "omitted_records" TEXT,
  "records__state" INTEGER NOT NULL CHECK("records__state" IN (2)),
  "records" TEXT,
  "includes_workflow__state" INTEGER NOT NULL CHECK("includes_workflow__state" IN (2)),
  "includes_workflow" INTEGER,
  CHECK(("id__state"=2 AND "id" IS NOT NULL) OR ("id__state" IN (0,1) AND "id" IS NULL)),
  CHECK(("owner__state"=2 AND "owner" IS NOT NULL) OR ("owner__state" IN (0,1) AND "owner" IS NULL)),
  CHECK(("source_digest__state"=2 AND "source_digest" IS NOT NULL) OR ("source_digest__state" IN (0,1) AND "source_digest" IS NULL)),
  CHECK(("target__state"=2 AND "target" IS NOT NULL) OR ("target__state" IN (0,1) AND "target" IS NULL)),
  CHECK(("source__state"=2 AND "source" IS NOT NULL) OR ("source__state" IN (0,1) AND "source" IS NULL)),
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("complete__state"=2 AND "complete" IS NOT NULL) OR ("complete__state" IN (0,1) AND "complete" IS NULL)),
  CHECK("complete" IN (0,1)),
  CHECK(("omitted_records__state"=2 AND "omitted_records" IS NOT NULL) OR ("omitted_records__state" IN (0,1) AND "omitted_records" IS NULL)),
  CHECK(("records__state"=2 AND "records" IS NOT NULL) OR ("records__state" IN (0,1) AND "records" IS NULL)),
  CHECK(("includes_workflow__state"=2 AND "includes_workflow" IS NOT NULL) OR ("includes_workflow__state" IN (0,1) AND "includes_workflow" IS NULL)),
  CHECK("includes_workflow" IN (0,1))
) STRICT;

CREATE TABLE "r_archive_manifest" (
  __row_id INTEGER PRIMARY KEY,
  "format__state" INTEGER NOT NULL CHECK("format__state" IN (2)),
  "format" TEXT,
  "universe__state" INTEGER NOT NULL CHECK("universe__state" IN (2)),
  "universe" TEXT,
  "name__state" INTEGER NOT NULL CHECK("name__state" IN (2)),
  "name" TEXT,
  "complete__state" INTEGER NOT NULL CHECK("complete__state" IN (2)),
  "complete" INTEGER,
  "omitted_records__state" INTEGER NOT NULL CHECK("omitted_records__state" IN (2)),
  "omitted_records" TEXT,
  "includes_history__state" INTEGER NOT NULL CHECK("includes_history__state" IN (2)),
  "includes_history" INTEGER,
  "includes_workflow__state" INTEGER NOT NULL CHECK("includes_workflow__state" IN (2)),
  "includes_workflow" INTEGER,
  CHECK(("format__state"=2 AND "format" IS NOT NULL) OR ("format__state" IN (0,1) AND "format" IS NULL)),
  CHECK(("universe__state"=2 AND "universe" IS NOT NULL) OR ("universe__state" IN (0,1) AND "universe" IS NULL)),
  CHECK(("name__state"=2 AND "name" IS NOT NULL) OR ("name__state" IN (0,1) AND "name" IS NULL)),
  CHECK(("complete__state"=2 AND "complete" IS NOT NULL) OR ("complete__state" IN (0,1) AND "complete" IS NULL)),
  CHECK("complete" IN (0,1)),
  CHECK(("omitted_records__state"=2 AND "omitted_records" IS NOT NULL) OR ("omitted_records__state" IN (0,1) AND "omitted_records" IS NULL)),
  CHECK(("includes_history__state"=2 AND "includes_history" IS NOT NULL) OR ("includes_history__state" IN (0,1) AND "includes_history" IS NULL)),
  CHECK("includes_history" IN (0,1)),
  CHECK(("includes_workflow__state"=2 AND "includes_workflow" IS NOT NULL) OR ("includes_workflow__state" IN (0,1) AND "includes_workflow" IS NULL)),
  CHECK("includes_workflow" IN (0,1))
) STRICT;

CREATE TABLE "r_source_validation_binding" (
  __row_id INTEGER PRIMARY KEY,
  "kind__state" INTEGER NOT NULL CHECK("kind__state" IN (2)),
  "kind" TEXT,
  "proposal__state" INTEGER NOT NULL CHECK("proposal__state" IN (2)),
  "proposal" INTEGER REFERENCES "r_proposal_ref"(__row_id),
  "base_frame__state" INTEGER NOT NULL CHECK("base_frame__state" IN (2)),
  "base_frame" INTEGER REFERENCES "r_frame"(__row_id),
  "selection__state" INTEGER NOT NULL CHECK("selection__state" IN (2)),
  "selection" INTEGER REFERENCES "r_assessment_selection"(__row_id),
  "submitted_input__state" INTEGER NOT NULL CHECK("submitted_input__state" IN (2)),
  "submitted_input" INTEGER REFERENCES "r_submitted_input"(__row_id),
  "assessment_state__state" INTEGER NOT NULL CHECK("assessment_state__state" IN (2)),
  "assessment_state" INTEGER REFERENCES "r_assessment_state"(__row_id),
  "execution_result_digest__state" INTEGER NOT NULL CHECK("execution_result_digest__state" IN (2)),
  "execution_result_digest" TEXT,
  "evaluator_version__state" INTEGER NOT NULL CHECK("evaluator_version__state" IN (2)),
  "evaluator_version" TEXT,
  CHECK(("kind__state"=2 AND "kind" IS NOT NULL) OR ("kind__state" IN (0,1) AND "kind" IS NULL)),
  CHECK("kind" IN ('source_validation_binding')),
  CHECK(("proposal__state"=2 AND "proposal" IS NOT NULL) OR ("proposal__state" IN (0,1) AND "proposal" IS NULL)),
  CHECK(("base_frame__state"=2 AND "base_frame" IS NOT NULL) OR ("base_frame__state" IN (0,1) AND "base_frame" IS NULL)),
  CHECK(("selection__state"=2 AND "selection" IS NOT NULL) OR ("selection__state" IN (0,1) AND "selection" IS NULL)),
  CHECK(("submitted_input__state"=2 AND "submitted_input" IS NOT NULL) OR ("submitted_input__state" IN (0,1) AND "submitted_input" IS NULL)),
  CHECK(("assessment_state__state"=2 AND "assessment_state" IS NOT NULL) OR ("assessment_state__state" IN (0,1) AND "assessment_state" IS NULL)),
  CHECK(("execution_result_digest__state"=2 AND "execution_result_digest" IS NOT NULL) OR ("execution_result_digest__state" IN (0,1) AND "execution_result_digest" IS NULL)),
  CHECK(("evaluator_version__state"=2 AND "evaluator_version" IS NOT NULL) OR ("evaluator_version__state" IN (0,1) AND "evaluator_version" IS NULL))
) STRICT;

CREATE TRIGGER "r_payload_no_update" BEFORE UPDATE ON "r_payload" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_no_delete" BEFORE DELETE ON "r_payload" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_no_update" BEFORE UPDATE ON "r_payload_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_no_delete" BEFORE DELETE ON "r_payload_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_names_no_update" BEFORE UPDATE ON "r_payload_v0_names" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_names_no_delete" BEFORE DELETE ON "r_payload_v0_names" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_names_items_no_update" BEFORE UPDATE ON "r_payload_v0_names_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_names_items_no_delete" BEFORE DELETE ON "r_payload_v0_names_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_contextual_name_no_update" BEFORE UPDATE ON "r_contextual_name" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_contextual_name_no_delete" BEFORE DELETE ON "r_contextual_name" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_contextual_name_language_no_update" BEFORE UPDATE ON "r_contextual_name_language" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_contextual_name_language_no_delete" BEFORE DELETE ON "r_contextual_name_language" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_contextual_name_community_no_update" BEFORE UPDATE ON "r_contextual_name_community" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_contextual_name_community_no_delete" BEFORE DELETE ON "r_contextual_name_community" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_contextual_name_role_no_update" BEFORE UPDATE ON "r_contextual_name_role" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_contextual_name_role_no_delete" BEFORE DELETE ON "r_contextual_name_role" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_no_update" BEFORE UPDATE ON "r_validity" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_no_delete" BEFORE DELETE ON "r_validity" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v0_no_update" BEFORE UPDATE ON "r_validity_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v0_no_delete" BEFORE DELETE ON "r_validity_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v1_no_update" BEFORE UPDATE ON "r_validity_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v1_no_delete" BEFORE DELETE ON "r_validity_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v2_no_update" BEFORE UPDATE ON "r_validity_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v2_no_delete" BEFORE DELETE ON "r_validity_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_no_update" BEFORE UPDATE ON "r_temporal_expression" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_no_delete" BEFORE DELETE ON "r_temporal_expression" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v0_no_update" BEFORE UPDATE ON "r_temporal_expression_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v0_no_delete" BEFORE DELETE ON "r_temporal_expression_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v1_no_update" BEFORE UPDATE ON "r_temporal_expression_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v1_no_delete" BEFORE DELETE ON "r_temporal_expression_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_no_update" BEFORE UPDATE ON "r_temporal_bound" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_no_delete" BEFORE DELETE ON "r_temporal_bound" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v0_no_update" BEFORE UPDATE ON "r_temporal_bound_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v0_no_delete" BEFORE DELETE ON "r_temporal_bound_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v1_no_update" BEFORE UPDATE ON "r_temporal_bound_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v1_no_delete" BEFORE DELETE ON "r_temporal_bound_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v2_no_update" BEFORE UPDATE ON "r_temporal_bound_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v2_no_delete" BEFORE DELETE ON "r_temporal_bound_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v3_no_update" BEFORE UPDATE ON "r_temporal_bound_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v3_no_delete" BEFORE DELETE ON "r_temporal_bound_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_no_update" BEFORE UPDATE ON "r_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_no_delete" BEFORE DELETE ON "r_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v0_no_update" BEFORE UPDATE ON "r_value_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v0_no_delete" BEFORE DELETE ON "r_value_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v1_no_update" BEFORE UPDATE ON "r_value_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v1_no_delete" BEFORE DELETE ON "r_value_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v2_no_update" BEFORE UPDATE ON "r_value_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v2_no_delete" BEFORE DELETE ON "r_value_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v3_no_update" BEFORE UPDATE ON "r_value_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v3_no_delete" BEFORE DELETE ON "r_value_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v4_no_update" BEFORE UPDATE ON "r_value_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v4_no_delete" BEFORE DELETE ON "r_value_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v5_no_update" BEFORE UPDATE ON "r_value_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v5_no_delete" BEFORE DELETE ON "r_value_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v6_no_update" BEFORE UPDATE ON "r_value_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v6_no_delete" BEFORE DELETE ON "r_value_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v6_unit_no_update" BEFORE UPDATE ON "r_value_v6_unit" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v6_unit_no_delete" BEFORE DELETE ON "r_value_v6_unit" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v7_no_update" BEFORE UPDATE ON "r_value_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v7_no_delete" BEFORE DELETE ON "r_value_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_record_ref_no_update" BEFORE UPDATE ON "r_record_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_record_ref_no_delete" BEFORE DELETE ON "r_record_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_record_ref_universe_no_update" BEFORE UPDATE ON "r_record_ref_universe" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_record_ref_universe_no_delete" BEFORE DELETE ON "r_record_ref_universe" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v8_no_update" BEFORE UPDATE ON "r_value_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v8_no_delete" BEFORE DELETE ON "r_value_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v9_no_update" BEFORE UPDATE ON "r_value_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v9_no_delete" BEFORE DELETE ON "r_value_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v10_no_update" BEFORE UPDATE ON "r_value_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v10_no_delete" BEFORE DELETE ON "r_value_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v11_no_update" BEFORE UPDATE ON "r_value_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v11_no_delete" BEFORE DELETE ON "r_value_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_no_update" BEFORE UPDATE ON "r_spatial_expression" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_no_delete" BEFORE DELETE ON "r_spatial_expression" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v0_no_update" BEFORE UPDATE ON "r_spatial_expression_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v0_no_delete" BEFORE DELETE ON "r_spatial_expression_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v1_no_update" BEFORE UPDATE ON "r_spatial_expression_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v1_no_delete" BEFORE DELETE ON "r_spatial_expression_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v2_no_update" BEFORE UPDATE ON "r_spatial_expression_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v2_no_delete" BEFORE DELETE ON "r_spatial_expression_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v3_no_update" BEFORE UPDATE ON "r_spatial_expression_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v3_no_delete" BEFORE DELETE ON "r_spatial_expression_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v3_values_no_update" BEFORE UPDATE ON "r_spatial_expression_v3_values" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v3_values_no_delete" BEFORE DELETE ON "r_spatial_expression_v3_values" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v3_values_items_no_update" BEFORE UPDATE ON "r_spatial_expression_v3_values_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v3_values_items_no_delete" BEFORE DELETE ON "r_spatial_expression_v3_values_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v4_no_update" BEFORE UPDATE ON "r_spatial_expression_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v4_no_delete" BEFORE DELETE ON "r_spatial_expression_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v5_no_update" BEFORE UPDATE ON "r_spatial_expression_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_spatial_expression_v5_no_delete" BEFORE DELETE ON "r_spatial_expression_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v12_no_update" BEFORE UPDATE ON "r_value_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v12_no_delete" BEFORE DELETE ON "r_value_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v13_no_update" BEFORE UPDATE ON "r_value_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v13_no_delete" BEFORE DELETE ON "r_value_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v13_items_no_update" BEFORE UPDATE ON "r_value_v13_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v13_items_no_delete" BEFORE DELETE ON "r_value_v13_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v13_items_items_no_update" BEFORE UPDATE ON "r_value_v13_items_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v13_items_items_no_delete" BEFORE DELETE ON "r_value_v13_items_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v14_no_update" BEFORE UPDATE ON "r_value_v14" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v14_no_delete" BEFORE DELETE ON "r_value_v14" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v14_items_no_update" BEFORE UPDATE ON "r_value_v14_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v14_items_no_delete" BEFORE DELETE ON "r_value_v14_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v14_items_items_no_update" BEFORE UPDATE ON "r_value_v14_items_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v14_items_items_no_delete" BEFORE DELETE ON "r_value_v14_items_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v15_no_update" BEFORE UPDATE ON "r_value_v15" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v15_no_delete" BEFORE DELETE ON "r_value_v15" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v15_fields_no_update" BEFORE UPDATE ON "r_value_v15_fields" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v15_fields_no_delete" BEFORE DELETE ON "r_value_v15_fields" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v15_fields_items_no_update" BEFORE UPDATE ON "r_value_v15_fields_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_v15_fields_items_no_delete" BEFORE DELETE ON "r_value_v15_fields_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v4_no_update" BEFORE UPDATE ON "r_temporal_bound_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_bound_v4_no_delete" BEFORE DELETE ON "r_temporal_bound_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v2_no_update" BEFORE UPDATE ON "r_temporal_expression_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v2_no_delete" BEFORE DELETE ON "r_temporal_expression_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v3_no_update" BEFORE UPDATE ON "r_temporal_expression_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v3_no_delete" BEFORE DELETE ON "r_temporal_expression_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v4_no_update" BEFORE UPDATE ON "r_temporal_expression_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v4_no_delete" BEFORE DELETE ON "r_temporal_expression_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_relation_no_update" BEFORE UPDATE ON "r_temporal_relation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_relation_no_delete" BEFORE DELETE ON "r_temporal_relation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v5_no_update" BEFORE UPDATE ON "r_temporal_expression_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_temporal_expression_v5_no_delete" BEFORE DELETE ON "r_temporal_expression_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v3_no_update" BEFORE UPDATE ON "r_validity_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v3_no_delete" BEFORE DELETE ON "r_validity_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v4_no_update" BEFORE UPDATE ON "r_validity_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v4_no_delete" BEFORE DELETE ON "r_validity_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v5_no_update" BEFORE UPDATE ON "r_validity_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v5_no_delete" BEFORE DELETE ON "r_validity_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v6_no_update" BEFORE UPDATE ON "r_validity_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validity_v6_no_delete" BEFORE DELETE ON "r_validity_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_classification_no_update" BEFORE UPDATE ON "r_payload_v0_classification" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_classification_no_delete" BEFORE DELETE ON "r_payload_v0_classification" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_world_associations_no_update" BEFORE UPDATE ON "r_payload_v0_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_world_associations_no_delete" BEFORE DELETE ON "r_payload_v0_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_world_associations_items_no_update" BEFORE UPDATE ON "r_payload_v0_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_world_associations_items_no_delete" BEFORE DELETE ON "r_payload_v0_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_association_no_update" BEFORE UPDATE ON "r_world_association" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_association_no_delete" BEFORE DELETE ON "r_world_association" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_association_qualifiers_no_update" BEFORE UPDATE ON "r_world_association_qualifiers" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_association_qualifiers_no_delete" BEFORE DELETE ON "r_world_association_qualifiers" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_association_qualifiers_items_no_update" BEFORE UPDATE ON "r_world_association_qualifiers_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_association_qualifiers_items_no_delete" BEFORE DELETE ON "r_world_association_qualifiers_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_labels_no_update" BEFORE UPDATE ON "r_payload_v0_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_labels_no_delete" BEFORE DELETE ON "r_payload_v0_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_labels_items_no_update" BEFORE UPDATE ON "r_payload_v0_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_labels_items_no_delete" BEFORE DELETE ON "r_payload_v0_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_metadata_no_update" BEFORE UPDATE ON "r_payload_v0_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_metadata_no_delete" BEFORE DELETE ON "r_payload_v0_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_metadata_items_no_update" BEFORE UPDATE ON "r_payload_v0_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v0_metadata_items_no_delete" BEFORE DELETE ON "r_payload_v0_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_no_update" BEFORE UPDATE ON "r_payload_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_no_delete" BEFORE DELETE ON "r_payload_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_target_no_update" BEFORE UPDATE ON "r_appearance_target" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_target_no_delete" BEFORE DELETE ON "r_appearance_target" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_target_v0_no_update" BEFORE UPDATE ON "r_appearance_target_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_target_v0_no_delete" BEFORE DELETE ON "r_appearance_target_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_target_v1_no_update" BEFORE UPDATE ON "r_appearance_target_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_target_v1_no_delete" BEFORE DELETE ON "r_appearance_target_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_images_no_update" BEFORE UPDATE ON "r_payload_v1_images" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_images_no_delete" BEFORE DELETE ON "r_payload_v1_images" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_images_items_no_update" BEFORE UPDATE ON "r_payload_v1_images_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_images_items_no_delete" BEFORE DELETE ON "r_payload_v1_images_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_image_no_update" BEFORE UPDATE ON "r_appearance_image" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_image_no_delete" BEFORE DELETE ON "r_appearance_image" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_links_no_update" BEFORE UPDATE ON "r_payload_v1_links" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_links_no_delete" BEFORE DELETE ON "r_payload_v1_links" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_links_items_no_update" BEFORE UPDATE ON "r_payload_v1_links_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v1_links_items_no_delete" BEFORE DELETE ON "r_payload_v1_links_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_link_no_update" BEFORE UPDATE ON "r_appearance_link" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_link_no_delete" BEFORE DELETE ON "r_appearance_link" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v2_no_update" BEFORE UPDATE ON "r_payload_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v2_no_delete" BEFORE DELETE ON "r_payload_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_no_update" BEFORE UPDATE ON "r_payload_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_no_delete" BEFORE DELETE ON "r_payload_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_aliases_no_update" BEFORE UPDATE ON "r_payload_v3_aliases" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_aliases_no_delete" BEFORE DELETE ON "r_payload_v3_aliases" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_aliases_items_no_update" BEFORE UPDATE ON "r_payload_v3_aliases_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_aliases_items_no_delete" BEFORE DELETE ON "r_payload_v3_aliases_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_setting_type_no_update" BEFORE UPDATE ON "r_payload_v3_setting_type" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_setting_type_no_delete" BEFORE DELETE ON "r_payload_v3_setting_type" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_labels_no_update" BEFORE UPDATE ON "r_payload_v3_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_labels_no_delete" BEFORE DELETE ON "r_payload_v3_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_labels_items_no_update" BEFORE UPDATE ON "r_payload_v3_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_labels_items_no_delete" BEFORE DELETE ON "r_payload_v3_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_metadata_no_update" BEFORE UPDATE ON "r_payload_v3_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_metadata_no_delete" BEFORE DELETE ON "r_payload_v3_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_metadata_items_no_update" BEFORE UPDATE ON "r_payload_v3_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v3_metadata_items_no_delete" BEFORE DELETE ON "r_payload_v3_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_no_update" BEFORE UPDATE ON "r_payload_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_no_delete" BEFORE DELETE ON "r_payload_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_labels_no_update" BEFORE UPDATE ON "r_payload_v4_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_labels_no_delete" BEFORE DELETE ON "r_payload_v4_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_labels_items_no_update" BEFORE UPDATE ON "r_payload_v4_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_labels_items_no_delete" BEFORE DELETE ON "r_payload_v4_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_metadata_no_update" BEFORE UPDATE ON "r_payload_v4_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_metadata_no_delete" BEFORE DELETE ON "r_payload_v4_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_metadata_items_no_update" BEFORE UPDATE ON "r_payload_v4_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v4_metadata_items_no_delete" BEFORE DELETE ON "r_payload_v4_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_no_update" BEFORE UPDATE ON "r_payload_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_no_delete" BEFORE DELETE ON "r_payload_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_kind_no_update" BEFORE UPDATE ON "r_work_kind" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_kind_no_delete" BEFORE DELETE ON "r_work_kind" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_labels_no_update" BEFORE UPDATE ON "r_payload_v5_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_labels_no_delete" BEFORE DELETE ON "r_payload_v5_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_labels_items_no_update" BEFORE UPDATE ON "r_payload_v5_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_labels_items_no_delete" BEFORE DELETE ON "r_payload_v5_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_source_refs_no_update" BEFORE UPDATE ON "r_payload_v5_source_refs" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_source_refs_no_delete" BEFORE DELETE ON "r_payload_v5_source_refs" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_source_refs_items_no_update" BEFORE UPDATE ON "r_payload_v5_source_refs_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_source_refs_items_no_delete" BEFORE DELETE ON "r_payload_v5_source_refs_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_versions_no_update" BEFORE UPDATE ON "r_payload_v5_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_versions_no_delete" BEFORE DELETE ON "r_payload_v5_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_versions_items_no_update" BEFORE UPDATE ON "r_payload_v5_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_versions_items_no_delete" BEFORE DELETE ON "r_payload_v5_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_world_associations_no_update" BEFORE UPDATE ON "r_payload_v5_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_world_associations_no_delete" BEFORE DELETE ON "r_payload_v5_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_world_associations_items_no_update" BEFORE UPDATE ON "r_payload_v5_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v5_world_associations_items_no_delete" BEFORE DELETE ON "r_payload_v5_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v6_no_update" BEFORE UPDATE ON "r_payload_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v6_no_delete" BEFORE DELETE ON "r_payload_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_no_update" BEFORE UPDATE ON "r_work_binding" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_no_delete" BEFORE DELETE ON "r_work_binding" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v0_no_update" BEFORE UPDATE ON "r_work_binding_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v0_no_delete" BEFORE DELETE ON "r_work_binding_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v1_no_update" BEFORE UPDATE ON "r_work_binding_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v1_no_delete" BEFORE DELETE ON "r_work_binding_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v2_no_update" BEFORE UPDATE ON "r_work_binding_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v2_no_delete" BEFORE DELETE ON "r_work_binding_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v2_segments_no_update" BEFORE UPDATE ON "r_work_binding_v2_segments" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v2_segments_no_delete" BEFORE DELETE ON "r_work_binding_v2_segments" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v2_segments_items_no_update" BEFORE UPDATE ON "r_work_binding_v2_segments_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_binding_v2_segments_items_no_delete" BEFORE DELETE ON "r_work_binding_v2_segments_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_segment_no_update" BEFORE UPDATE ON "r_work_segment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_segment_no_delete" BEFORE DELETE ON "r_work_segment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_no_update" BEFORE UPDATE ON "r_payload_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_no_delete" BEFORE DELETE ON "r_payload_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_version_ref_no_update" BEFORE UPDATE ON "r_version_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_version_ref_no_delete" BEFORE DELETE ON "r_version_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_version_ref_universe_no_update" BEFORE UPDATE ON "r_version_ref_universe" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_version_ref_universe_no_delete" BEFORE DELETE ON "r_version_ref_universe" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_disclosed_records_no_update" BEFORE UPDATE ON "r_payload_v7_disclosed_records" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_disclosed_records_no_delete" BEFORE DELETE ON "r_payload_v7_disclosed_records" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_disclosed_records_items_no_update" BEFORE UPDATE ON "r_payload_v7_disclosed_records_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_disclosed_records_items_no_delete" BEFORE DELETE ON "r_payload_v7_disclosed_records_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_viewpoint_no_update" BEFORE UPDATE ON "r_payload_v7_viewpoint" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_viewpoint_no_delete" BEFORE DELETE ON "r_payload_v7_viewpoint" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_narrative_position_no_update" BEFORE UPDATE ON "r_payload_v7_narrative_position" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_narrative_position_no_delete" BEFORE DELETE ON "r_payload_v7_narrative_position" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_depicted_events_no_update" BEFORE UPDATE ON "r_payload_v7_depicted_events" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_depicted_events_no_delete" BEFORE DELETE ON "r_payload_v7_depicted_events" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_depicted_events_items_no_update" BEFORE UPDATE ON "r_payload_v7_depicted_events_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_depicted_events_items_no_delete" BEFORE DELETE ON "r_payload_v7_depicted_events_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_narration_frame_no_update" BEFORE UPDATE ON "r_payload_v7_narration_frame" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_narration_frame_no_delete" BEFORE DELETE ON "r_payload_v7_narration_frame" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_world_associations_no_update" BEFORE UPDATE ON "r_payload_v7_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_world_associations_no_delete" BEFORE DELETE ON "r_payload_v7_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_world_associations_items_no_update" BEFORE UPDATE ON "r_payload_v7_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v7_world_associations_items_no_delete" BEFORE DELETE ON "r_payload_v7_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v8_no_update" BEFORE UPDATE ON "r_payload_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v8_no_delete" BEFORE DELETE ON "r_payload_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v8_anchor_no_update" BEFORE UPDATE ON "r_payload_v8_anchor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v8_anchor_no_delete" BEFORE DELETE ON "r_payload_v8_anchor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_no_update" BEFORE UPDATE ON "r_payload_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_no_delete" BEFORE DELETE ON "r_payload_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_labels_no_update" BEFORE UPDATE ON "r_payload_v9_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_labels_no_delete" BEFORE DELETE ON "r_payload_v9_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_labels_items_no_update" BEFORE UPDATE ON "r_payload_v9_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_labels_items_no_delete" BEFORE DELETE ON "r_payload_v9_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_memberships_no_update" BEFORE UPDATE ON "r_payload_v9_memberships" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_memberships_no_delete" BEFORE DELETE ON "r_payload_v9_memberships" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_memberships_items_no_update" BEFORE UPDATE ON "r_payload_v9_memberships_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v9_memberships_items_no_delete" BEFORE DELETE ON "r_payload_v9_memberships_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_membership_no_update" BEFORE UPDATE ON "r_saga_membership" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_membership_no_delete" BEFORE DELETE ON "r_saga_membership" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_membership_order_no_update" BEFORE UPDATE ON "r_saga_membership_order" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_membership_order_no_delete" BEFORE DELETE ON "r_saga_membership_order" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v10_no_update" BEFORE UPDATE ON "r_payload_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v10_no_delete" BEFORE DELETE ON "r_payload_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v10_labels_no_update" BEFORE UPDATE ON "r_payload_v10_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v10_labels_no_delete" BEFORE DELETE ON "r_payload_v10_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v10_labels_items_no_update" BEFORE UPDATE ON "r_payload_v10_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v10_labels_items_no_delete" BEFORE DELETE ON "r_payload_v10_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v10_parent_no_update" BEFORE UPDATE ON "r_payload_v10_parent" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v10_parent_no_delete" BEFORE DELETE ON "r_payload_v10_parent" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_no_update" BEFORE UPDATE ON "r_applicability" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_no_delete" BEFORE DELETE ON "r_applicability" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v0_no_update" BEFORE UPDATE ON "r_applicability_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v0_no_delete" BEFORE DELETE ON "r_applicability_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v1_no_update" BEFORE UPDATE ON "r_applicability_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v1_no_delete" BEFORE DELETE ON "r_applicability_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v1_world_ids_no_update" BEFORE UPDATE ON "r_applicability_v1_world_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v1_world_ids_no_delete" BEFORE DELETE ON "r_applicability_v1_world_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v1_world_ids_items_no_update" BEFORE UPDATE ON "r_applicability_v1_world_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v1_world_ids_items_no_delete" BEFORE DELETE ON "r_applicability_v1_world_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v2_no_update" BEFORE UPDATE ON "r_applicability_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v2_no_delete" BEFORE DELETE ON "r_applicability_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v3_no_update" BEFORE UPDATE ON "r_applicability_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_applicability_v3_no_delete" BEFORE DELETE ON "r_applicability_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_no_update" BEFORE UPDATE ON "r_payload_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_no_delete" BEFORE DELETE ON "r_payload_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_labels_no_update" BEFORE UPDATE ON "r_payload_v11_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_labels_no_delete" BEFORE DELETE ON "r_payload_v11_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_labels_items_no_update" BEFORE UPDATE ON "r_payload_v11_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_labels_items_no_delete" BEFORE DELETE ON "r_payload_v11_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_subject_types_no_update" BEFORE UPDATE ON "r_payload_v11_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_subject_types_no_delete" BEFORE DELETE ON "r_payload_v11_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_subject_types_items_no_update" BEFORE UPDATE ON "r_payload_v11_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_subject_types_items_no_delete" BEFORE DELETE ON "r_payload_v11_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_no_update" BEFORE UPDATE ON "r_value_shape" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_no_delete" BEFORE DELETE ON "r_value_shape" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v0_no_update" BEFORE UPDATE ON "r_value_shape_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v0_no_delete" BEFORE DELETE ON "r_value_shape_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v1_no_update" BEFORE UPDATE ON "r_value_shape_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v1_no_delete" BEFORE DELETE ON "r_value_shape_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v2_no_update" BEFORE UPDATE ON "r_value_shape_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v2_no_delete" BEFORE DELETE ON "r_value_shape_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v3_no_update" BEFORE UPDATE ON "r_value_shape_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v3_no_delete" BEFORE DELETE ON "r_value_shape_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v4_no_update" BEFORE UPDATE ON "r_value_shape_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v4_no_delete" BEFORE DELETE ON "r_value_shape_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v5_no_update" BEFORE UPDATE ON "r_value_shape_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v5_no_delete" BEFORE DELETE ON "r_value_shape_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v6_no_update" BEFORE UPDATE ON "r_value_shape_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v6_no_delete" BEFORE DELETE ON "r_value_shape_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v6_unit_no_update" BEFORE UPDATE ON "r_value_shape_v6_unit" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v6_unit_no_delete" BEFORE DELETE ON "r_value_shape_v6_unit" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v7_no_update" BEFORE UPDATE ON "r_value_shape_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v7_no_delete" BEFORE DELETE ON "r_value_shape_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v7_subject_types_no_update" BEFORE UPDATE ON "r_value_shape_v7_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v7_subject_types_no_delete" BEFORE DELETE ON "r_value_shape_v7_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v7_subject_types_items_no_update" BEFORE UPDATE ON "r_value_shape_v7_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v7_subject_types_items_no_delete" BEFORE DELETE ON "r_value_shape_v7_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v8_no_update" BEFORE UPDATE ON "r_value_shape_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v8_no_delete" BEFORE DELETE ON "r_value_shape_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v9_no_update" BEFORE UPDATE ON "r_value_shape_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v9_no_delete" BEFORE DELETE ON "r_value_shape_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v10_no_update" BEFORE UPDATE ON "r_value_shape_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v10_no_delete" BEFORE DELETE ON "r_value_shape_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v11_no_update" BEFORE UPDATE ON "r_value_shape_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v11_no_delete" BEFORE DELETE ON "r_value_shape_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v12_no_update" BEFORE UPDATE ON "r_value_shape_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v12_no_delete" BEFORE DELETE ON "r_value_shape_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v13_no_update" BEFORE UPDATE ON "r_value_shape_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_shape_v13_no_delete" BEFORE DELETE ON "r_value_shape_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_unit_dimension_no_update" BEFORE UPDATE ON "r_payload_v11_unit_dimension" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_unit_dimension_no_delete" BEFORE DELETE ON "r_payload_v11_unit_dimension" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_persistence_semantics_no_update" BEFORE UPDATE ON "r_persistence_semantics" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_persistence_semantics_no_delete" BEFORE DELETE ON "r_persistence_semantics" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_inverse_no_update" BEFORE UPDATE ON "r_payload_v11_inverse" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v11_inverse_no_delete" BEFORE DELETE ON "r_payload_v11_inverse" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_no_update" BEFORE UPDATE ON "r_payload_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_no_delete" BEFORE DELETE ON "r_payload_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_labels_no_update" BEFORE UPDATE ON "r_payload_v12_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_labels_no_delete" BEFORE DELETE ON "r_payload_v12_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_labels_items_no_update" BEFORE UPDATE ON "r_payload_v12_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_labels_items_no_delete" BEFORE DELETE ON "r_payload_v12_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_roles_no_update" BEFORE UPDATE ON "r_payload_v12_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_roles_no_delete" BEFORE DELETE ON "r_payload_v12_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_roles_items_no_update" BEFORE UPDATE ON "r_payload_v12_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v12_roles_items_no_delete" BEFORE DELETE ON "r_payload_v12_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_role_def_no_update" BEFORE UPDATE ON "r_role_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_role_def_no_delete" BEFORE DELETE ON "r_role_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_role_def_participant_types_no_update" BEFORE UPDATE ON "r_role_def_participant_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_role_def_participant_types_no_delete" BEFORE DELETE ON "r_role_def_participant_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_role_def_participant_types_items_no_update" BEFORE UPDATE ON "r_role_def_participant_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_role_def_participant_types_items_no_delete" BEFORE DELETE ON "r_role_def_participant_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_no_update" BEFORE UPDATE ON "r_payload_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_no_delete" BEFORE DELETE ON "r_payload_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_labels_no_update" BEFORE UPDATE ON "r_payload_v13_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_labels_no_delete" BEFORE DELETE ON "r_payload_v13_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_labels_items_no_update" BEFORE UPDATE ON "r_payload_v13_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_labels_items_no_delete" BEFORE DELETE ON "r_payload_v13_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_scale_to_base_no_update" BEFORE UPDATE ON "r_payload_v13_scale_to_base" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_scale_to_base_no_delete" BEFORE DELETE ON "r_payload_v13_scale_to_base" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_base_no_update" BEFORE UPDATE ON "r_payload_v13_base" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v13_base_no_delete" BEFORE DELETE ON "r_payload_v13_base" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_no_update" BEFORE UPDATE ON "r_payload_v14" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_no_delete" BEFORE DELETE ON "r_payload_v14" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_labels_no_update" BEFORE UPDATE ON "r_payload_v14_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_labels_no_delete" BEFORE DELETE ON "r_payload_v14_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_labels_items_no_update" BEFORE UPDATE ON "r_payload_v14_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_labels_items_no_delete" BEFORE DELETE ON "r_payload_v14_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_epoch_no_update" BEFORE UPDATE ON "r_payload_v14_epoch" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_epoch_no_delete" BEFORE DELETE ON "r_payload_v14_epoch" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_unit_structure_no_update" BEFORE UPDATE ON "r_payload_v14_unit_structure" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_unit_structure_no_delete" BEFORE DELETE ON "r_payload_v14_unit_structure" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_unit_structure_items_no_update" BEFORE UPDATE ON "r_payload_v14_unit_structure_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_unit_structure_items_no_delete" BEFORE DELETE ON "r_payload_v14_unit_structure_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_conversions_no_update" BEFORE UPDATE ON "r_payload_v14_conversions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_conversions_no_delete" BEFORE DELETE ON "r_payload_v14_conversions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_conversions_items_no_update" BEFORE UPDATE ON "r_payload_v14_conversions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v14_conversions_items_no_delete" BEFORE DELETE ON "r_payload_v14_conversions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_conversion_no_update" BEFORE UPDATE ON "r_calendar_conversion" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_conversion_no_delete" BEFORE DELETE ON "r_calendar_conversion" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_conversion_expression_no_update" BEFORE UPDATE ON "r_calendar_conversion_expression" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_conversion_expression_no_delete" BEFORE DELETE ON "r_calendar_conversion_expression" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_no_update" BEFORE UPDATE ON "r_payload_v15" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_no_delete" BEFORE DELETE ON "r_payload_v15" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_labels_no_update" BEFORE UPDATE ON "r_payload_v15_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_labels_no_delete" BEFORE DELETE ON "r_payload_v15_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_labels_items_no_update" BEFORE UPDATE ON "r_payload_v15_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_labels_items_no_delete" BEFORE DELETE ON "r_payload_v15_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_fields_no_update" BEFORE UPDATE ON "r_payload_v15_fields" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_fields_no_delete" BEFORE DELETE ON "r_payload_v15_fields" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_fields_items_no_update" BEFORE UPDATE ON "r_payload_v15_fields_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v15_fields_items_no_delete" BEFORE DELETE ON "r_payload_v15_fields_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_field_no_update" BEFORE UPDATE ON "r_value_def_field" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_field_no_delete" BEFORE DELETE ON "r_value_def_field" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_no_update" BEFORE UPDATE ON "r_payload_v16" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_no_delete" BEFORE DELETE ON "r_payload_v16" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_dependencies_no_update" BEFORE UPDATE ON "r_payload_v16_dependencies" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_dependencies_no_delete" BEFORE DELETE ON "r_payload_v16_dependencies" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_dependencies_items_no_update" BEFORE UPDATE ON "r_payload_v16_dependencies_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_dependencies_items_no_delete" BEFORE DELETE ON "r_payload_v16_dependencies_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_capabilities_no_update" BEFORE UPDATE ON "r_payload_v16_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_capabilities_no_delete" BEFORE DELETE ON "r_payload_v16_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_capabilities_items_no_update" BEFORE UPDATE ON "r_payload_v16_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_capabilities_items_no_delete" BEFORE DELETE ON "r_payload_v16_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_records_no_update" BEFORE UPDATE ON "r_payload_v16_records" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_records_no_delete" BEFORE DELETE ON "r_payload_v16_records" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_records_items_no_update" BEFORE UPDATE ON "r_payload_v16_records_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v16_records_items_no_delete" BEFORE DELETE ON "r_payload_v16_records_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v17_no_update" BEFORE UPDATE ON "r_payload_v17" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v17_no_delete" BEFORE DELETE ON "r_payload_v17" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v17_roles_no_update" BEFORE UPDATE ON "r_payload_v17_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v17_roles_no_delete" BEFORE DELETE ON "r_payload_v17_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v17_roles_items_no_update" BEFORE UPDATE ON "r_payload_v17_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v17_roles_items_no_delete" BEFORE DELETE ON "r_payload_v17_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_role_no_update" BEFORE UPDATE ON "r_proposition_role" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_role_no_delete" BEFORE DELETE ON "r_proposition_role" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v17_value_no_update" BEFORE UPDATE ON "r_payload_v17_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v17_value_no_delete" BEFORE DELETE ON "r_payload_v17_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_quantification_no_update" BEFORE UPDATE ON "r_quantification" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_quantification_no_delete" BEFORE DELETE ON "r_quantification" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v18_no_update" BEFORE UPDATE ON "r_payload_v18" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v18_no_delete" BEFORE DELETE ON "r_payload_v18" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_scope_no_update" BEFORE UPDATE ON "r_scope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_scope_no_delete" BEFORE DELETE ON "r_scope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_scope_realm_no_update" BEFORE UPDATE ON "r_scope_realm" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_scope_realm_no_delete" BEFORE DELETE ON "r_scope_realm" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v18_alternatives_no_update" BEFORE UPDATE ON "r_payload_v18_alternatives" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v18_alternatives_no_delete" BEFORE DELETE ON "r_payload_v18_alternatives" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v18_alternatives_items_no_update" BEFORE UPDATE ON "r_payload_v18_alternatives_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v18_alternatives_items_no_delete" BEFORE DELETE ON "r_payload_v18_alternatives_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_no_update" BEFORE UPDATE ON "r_evidence_basis" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_no_delete" BEFORE DELETE ON "r_evidence_basis" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v0_no_update" BEFORE UPDATE ON "r_evidence_basis_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v0_no_delete" BEFORE DELETE ON "r_evidence_basis_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v1_no_update" BEFORE UPDATE ON "r_evidence_basis_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v1_no_delete" BEFORE DELETE ON "r_evidence_basis_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v2_no_update" BEFORE UPDATE ON "r_evidence_basis_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v2_no_delete" BEFORE DELETE ON "r_evidence_basis_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v3_no_update" BEFORE UPDATE ON "r_evidence_basis_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v3_no_delete" BEFORE DELETE ON "r_evidence_basis_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v4_no_update" BEFORE UPDATE ON "r_evidence_basis_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v4_no_delete" BEFORE DELETE ON "r_evidence_basis_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v5_no_update" BEFORE UPDATE ON "r_evidence_basis_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v5_no_delete" BEFORE DELETE ON "r_evidence_basis_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v5_chain_no_update" BEFORE UPDATE ON "r_evidence_basis_v5_chain" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v5_chain_no_delete" BEFORE DELETE ON "r_evidence_basis_v5_chain" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v5_chain_items_no_update" BEFORE UPDATE ON "r_evidence_basis_v5_chain_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v5_chain_items_no_delete" BEFORE DELETE ON "r_evidence_basis_v5_chain_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v5_evaluator_no_update" BEFORE UPDATE ON "r_evidence_basis_v5_evaluator" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v5_evaluator_no_delete" BEFORE DELETE ON "r_evidence_basis_v5_evaluator" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v6_no_update" BEFORE UPDATE ON "r_evidence_basis_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_evidence_basis_v6_no_delete" BEFORE DELETE ON "r_evidence_basis_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v18_established_by_no_update" BEFORE UPDATE ON "r_payload_v18_established_by" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v18_established_by_no_delete" BEFORE DELETE ON "r_payload_v18_established_by" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_effect_ref_no_update" BEFORE UPDATE ON "r_event_effect_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_effect_ref_no_delete" BEFORE DELETE ON "r_event_effect_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_no_update" BEFORE UPDATE ON "r_payload_v19" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_no_delete" BEFORE DELETE ON "r_payload_v19" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_no_update" BEFORE UPDATE ON "r_represented_context_kind" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_no_delete" BEFORE DELETE ON "r_represented_context_kind" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v0_no_update" BEFORE UPDATE ON "r_represented_context_kind_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v0_no_delete" BEFORE DELETE ON "r_represented_context_kind_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v1_no_update" BEFORE UPDATE ON "r_represented_context_kind_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v1_no_delete" BEFORE DELETE ON "r_represented_context_kind_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v2_no_update" BEFORE UPDATE ON "r_represented_context_kind_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v2_no_delete" BEFORE DELETE ON "r_represented_context_kind_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v3_no_update" BEFORE UPDATE ON "r_represented_context_kind_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v3_no_delete" BEFORE DELETE ON "r_represented_context_kind_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v4_no_update" BEFORE UPDATE ON "r_represented_context_kind_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_represented_context_kind_v4_no_delete" BEFORE DELETE ON "r_represented_context_kind_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_parent_no_update" BEFORE UPDATE ON "r_payload_v19_parent" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_parent_no_delete" BEFORE DELETE ON "r_payload_v19_parent" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_chronology_no_update" BEFORE UPDATE ON "r_payload_v19_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_chronology_no_delete" BEFORE DELETE ON "r_payload_v19_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_chronology_no_update" BEFORE UPDATE ON "r_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_chronology_no_delete" BEFORE DELETE ON "r_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_clock_system_no_update" BEFORE UPDATE ON "r_clock_system" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_clock_system_no_delete" BEFORE DELETE ON "r_clock_system" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_clock_system_v0_no_update" BEFORE UPDATE ON "r_clock_system_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_clock_system_v0_no_delete" BEFORE DELETE ON "r_clock_system_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_clock_system_v1_no_update" BEFORE UPDATE ON "r_clock_system_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_clock_system_v1_no_delete" BEFORE DELETE ON "r_clock_system_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_clock_system_v1_ticks_per_month_no_update" BEFORE UPDATE ON "r_clock_system_v1_ticks_per_month" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_clock_system_v1_ticks_per_month_no_delete" BEFORE DELETE ON "r_clock_system_v1_ticks_per_month" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_labels_no_update" BEFORE UPDATE ON "r_payload_v19_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_labels_no_delete" BEFORE DELETE ON "r_payload_v19_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_labels_items_no_update" BEFORE UPDATE ON "r_payload_v19_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v19_labels_items_no_delete" BEFORE DELETE ON "r_payload_v19_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v20_no_update" BEFORE UPDATE ON "r_payload_v20" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v20_no_delete" BEFORE DELETE ON "r_payload_v20" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v20_members_no_update" BEFORE UPDATE ON "r_payload_v20_members" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v20_members_no_delete" BEFORE DELETE ON "r_payload_v20_members" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v20_members_items_no_update" BEFORE UPDATE ON "r_payload_v20_members_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v20_members_items_no_delete" BEFORE DELETE ON "r_payload_v20_members_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_kind_no_update" BEFORE UPDATE ON "r_completeness_kind" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_kind_no_delete" BEFORE DELETE ON "r_completeness_kind" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_kind_v1_no_update" BEFORE UPDATE ON "r_completeness_kind_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_kind_v1_no_delete" BEFORE DELETE ON "r_completeness_kind_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_kind_v1_observer_known_no_update" BEFORE UPDATE ON "r_completeness_kind_v1_observer_known" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_kind_v1_observer_known_no_delete" BEFORE DELETE ON "r_completeness_kind_v1_observer_known" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v21_no_update" BEFORE UPDATE ON "r_payload_v21" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v21_no_delete" BEFORE DELETE ON "r_payload_v21" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_no_update" BEFORE UPDATE ON "r_boundary_area" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_no_delete" BEFORE DELETE ON "r_boundary_area" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v0_no_update" BEFORE UPDATE ON "r_boundary_area_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v0_no_delete" BEFORE DELETE ON "r_boundary_area_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v0_universe_no_update" BEFORE UPDATE ON "r_boundary_area_v0_universe" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v0_universe_no_delete" BEFORE DELETE ON "r_boundary_area_v0_universe" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v1_no_update" BEFORE UPDATE ON "r_boundary_area_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v1_no_delete" BEFORE DELETE ON "r_boundary_area_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v1_subject_no_update" BEFORE UPDATE ON "r_boundary_area_v1_subject" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v1_subject_no_delete" BEFORE DELETE ON "r_boundary_area_v1_subject" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v2_no_update" BEFORE UPDATE ON "r_boundary_area_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_area_v2_no_delete" BEFORE DELETE ON "r_boundary_area_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_mode_no_update" BEFORE UPDATE ON "r_boundary_mode" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_boundary_mode_no_delete" BEFORE DELETE ON "r_boundary_mode" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v21_constraints_no_update" BEFORE UPDATE ON "r_payload_v21_constraints" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v21_constraints_no_delete" BEFORE DELETE ON "r_payload_v21_constraints" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v21_constraints_items_no_update" BEFORE UPDATE ON "r_payload_v21_constraints_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v21_constraints_items_no_delete" BEFORE DELETE ON "r_payload_v21_constraints_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_no_update" BEFORE UPDATE ON "r_expr" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_no_delete" BEFORE DELETE ON "r_expr" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v0_no_update" BEFORE UPDATE ON "r_expr_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v0_no_delete" BEFORE DELETE ON "r_expr_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_no_update" BEFORE UPDATE ON "r_operand" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_no_delete" BEFORE DELETE ON "r_operand" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v0_no_update" BEFORE UPDATE ON "r_operand_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v0_no_delete" BEFORE DELETE ON "r_operand_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v1_no_update" BEFORE UPDATE ON "r_operand_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v1_no_delete" BEFORE DELETE ON "r_operand_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v2_no_update" BEFORE UPDATE ON "r_operand_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v2_no_delete" BEFORE DELETE ON "r_operand_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v3_no_update" BEFORE UPDATE ON "r_operand_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v3_no_delete" BEFORE DELETE ON "r_operand_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v4_no_update" BEFORE UPDATE ON "r_operand_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v4_no_delete" BEFORE DELETE ON "r_operand_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v5_no_update" BEFORE UPDATE ON "r_operand_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operand_v5_no_delete" BEFORE DELETE ON "r_operand_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v1_no_update" BEFORE UPDATE ON "r_expr_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v1_no_delete" BEFORE DELETE ON "r_expr_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v2_no_update" BEFORE UPDATE ON "r_expr_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v2_no_delete" BEFORE DELETE ON "r_expr_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v3_no_update" BEFORE UPDATE ON "r_expr_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v3_no_delete" BEFORE DELETE ON "r_expr_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v4_no_update" BEFORE UPDATE ON "r_expr_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v4_no_delete" BEFORE DELETE ON "r_expr_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v4_exprs_no_update" BEFORE UPDATE ON "r_expr_v4_exprs" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v4_exprs_no_delete" BEFORE DELETE ON "r_expr_v4_exprs" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v4_exprs_items_no_update" BEFORE UPDATE ON "r_expr_v4_exprs_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v4_exprs_items_no_delete" BEFORE DELETE ON "r_expr_v4_exprs_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v5_no_update" BEFORE UPDATE ON "r_expr_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v5_no_delete" BEFORE DELETE ON "r_expr_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v5_exprs_no_update" BEFORE UPDATE ON "r_expr_v5_exprs" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v5_exprs_no_delete" BEFORE DELETE ON "r_expr_v5_exprs" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v5_exprs_items_no_update" BEFORE UPDATE ON "r_expr_v5_exprs_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v5_exprs_items_no_delete" BEFORE DELETE ON "r_expr_v5_exprs_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_no_update" BEFORE UPDATE ON "r_expr_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_no_delete" BEFORE DELETE ON "r_expr_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_roles_no_update" BEFORE UPDATE ON "r_expr_v6_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_roles_no_delete" BEFORE DELETE ON "r_expr_v6_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_roles_items_no_update" BEFORE UPDATE ON "r_expr_v6_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_roles_items_no_delete" BEFORE DELETE ON "r_expr_v6_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_roles_item_no_update" BEFORE UPDATE ON "r_expr_v6_roles_item" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_roles_item_no_delete" BEFORE DELETE ON "r_expr_v6_roles_item" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_value_no_update" BEFORE UPDATE ON "r_expr_v6_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_value_no_delete" BEFORE DELETE ON "r_expr_v6_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_context_no_update" BEFORE UPDATE ON "r_expr_v6_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v6_context_no_delete" BEFORE DELETE ON "r_expr_v6_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_no_update" BEFORE UPDATE ON "r_expr_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_no_delete" BEFORE DELETE ON "r_expr_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_roles_no_update" BEFORE UPDATE ON "r_expr_v7_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_roles_no_delete" BEFORE DELETE ON "r_expr_v7_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_roles_items_no_update" BEFORE UPDATE ON "r_expr_v7_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_roles_items_no_delete" BEFORE DELETE ON "r_expr_v7_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_roles_item_no_update" BEFORE UPDATE ON "r_expr_v7_roles_item" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_roles_item_no_delete" BEFORE DELETE ON "r_expr_v7_roles_item" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_value_no_update" BEFORE UPDATE ON "r_expr_v7_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_value_no_delete" BEFORE DELETE ON "r_expr_v7_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_context_no_update" BEFORE UPDATE ON "r_expr_v7_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v7_context_no_delete" BEFORE DELETE ON "r_expr_v7_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v8_no_update" BEFORE UPDATE ON "r_expr_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v8_no_delete" BEFORE DELETE ON "r_expr_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v9_no_update" BEFORE UPDATE ON "r_expr_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v9_no_delete" BEFORE DELETE ON "r_expr_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v10_no_update" BEFORE UPDATE ON "r_expr_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v10_no_delete" BEFORE DELETE ON "r_expr_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v10_complete_no_update" BEFORE UPDATE ON "r_expr_v10_complete" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v10_complete_no_delete" BEFORE DELETE ON "r_expr_v10_complete" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v11_no_update" BEFORE UPDATE ON "r_expr_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v11_no_delete" BEFORE DELETE ON "r_expr_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v11_complete_no_update" BEFORE UPDATE ON "r_expr_v11_complete" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v11_complete_no_delete" BEFORE DELETE ON "r_expr_v11_complete" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_no_update" BEFORE UPDATE ON "r_expr_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_no_delete" BEFORE DELETE ON "r_expr_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_roles_no_update" BEFORE UPDATE ON "r_expr_v12_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_roles_no_delete" BEFORE DELETE ON "r_expr_v12_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_roles_items_no_update" BEFORE UPDATE ON "r_expr_v12_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_roles_items_no_delete" BEFORE DELETE ON "r_expr_v12_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_roles_item_no_update" BEFORE UPDATE ON "r_expr_v12_roles_item" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_roles_item_no_delete" BEFORE DELETE ON "r_expr_v12_roles_item" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_value_no_update" BEFORE UPDATE ON "r_expr_v12_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_value_no_delete" BEFORE DELETE ON "r_expr_v12_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_context_no_update" BEFORE UPDATE ON "r_expr_v12_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v12_context_no_delete" BEFORE DELETE ON "r_expr_v12_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v13_no_update" BEFORE UPDATE ON "r_expr_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v13_no_delete" BEFORE DELETE ON "r_expr_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v14_no_update" BEFORE UPDATE ON "r_expr_v14" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_expr_v14_no_delete" BEFORE DELETE ON "r_expr_v14" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_no_update" BEFORE UPDATE ON "r_payload_v22" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_no_delete" BEFORE DELETE ON "r_payload_v22" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_knowledge_policy_no_update" BEFORE UPDATE ON "r_payload_v22_knowledge_policy" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_knowledge_policy_no_delete" BEFORE DELETE ON "r_payload_v22_knowledge_policy" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_policy_no_update" BEFORE UPDATE ON "r_knowledge_policy" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_policy_no_delete" BEFORE DELETE ON "r_knowledge_policy" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_channel_chronology_no_update" BEFORE UPDATE ON "r_payload_v22_channel_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_channel_chronology_no_delete" BEFORE DELETE ON "r_payload_v22_channel_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_channel_chronology_no_update" BEFORE UPDATE ON "r_channel_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_channel_chronology_no_delete" BEFORE DELETE ON "r_channel_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_channel_chronology_minimum_delay_no_update" BEFORE UPDATE ON "r_channel_chronology_minimum_delay" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_channel_chronology_minimum_delay_no_delete" BEFORE DELETE ON "r_channel_chronology_minimum_delay" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_channel_chronology_maximum_delay_no_update" BEFORE UPDATE ON "r_channel_chronology_maximum_delay" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_channel_chronology_maximum_delay_no_delete" BEFORE DELETE ON "r_channel_chronology_maximum_delay" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_labels_no_update" BEFORE UPDATE ON "r_payload_v22_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_labels_no_delete" BEFORE DELETE ON "r_payload_v22_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_labels_items_no_update" BEFORE UPDATE ON "r_payload_v22_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_labels_items_no_delete" BEFORE DELETE ON "r_payload_v22_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_kind_no_update" BEFORE UPDATE ON "r_rule_kind" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_kind_no_delete" BEFORE DELETE ON "r_rule_kind" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_policy_no_update" BEFORE UPDATE ON "r_commit_policy" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_policy_no_delete" BEFORE DELETE ON "r_commit_policy" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_subject_types_no_update" BEFORE UPDATE ON "r_payload_v22_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_subject_types_no_delete" BEFORE DELETE ON "r_payload_v22_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_subject_types_items_no_update" BEFORE UPDATE ON "r_payload_v22_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_subject_types_items_no_delete" BEFORE DELETE ON "r_payload_v22_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_target_predicates_no_update" BEFORE UPDATE ON "r_payload_v22_target_predicates" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_target_predicates_no_delete" BEFORE DELETE ON "r_payload_v22_target_predicates" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_target_predicates_items_no_update" BEFORE UPDATE ON "r_payload_v22_target_predicates_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_target_predicates_items_no_delete" BEFORE DELETE ON "r_payload_v22_target_predicates_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_capabilities_no_update" BEFORE UPDATE ON "r_payload_v22_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_capabilities_no_delete" BEFORE DELETE ON "r_payload_v22_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_capabilities_items_no_update" BEFORE UPDATE ON "r_payload_v22_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v22_capabilities_items_no_delete" BEFORE DELETE ON "r_payload_v22_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v23_no_update" BEFORE UPDATE ON "r_payload_v23" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v23_no_delete" BEFORE DELETE ON "r_payload_v23" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v23_rule_version_no_update" BEFORE UPDATE ON "r_payload_v23_rule_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v23_rule_version_no_delete" BEFORE DELETE ON "r_payload_v23_rule_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_no_update" BEFORE UPDATE ON "r_payload_v24" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_no_delete" BEFORE DELETE ON "r_payload_v24" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_occurrence_mode_no_update" BEFORE UPDATE ON "r_occurrence_mode" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_occurrence_mode_no_delete" BEFORE DELETE ON "r_occurrence_mode" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_occurrence_mode_v1_no_update" BEFORE UPDATE ON "r_occurrence_mode_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_occurrence_mode_v1_no_delete" BEFORE DELETE ON "r_occurrence_mode_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_occurrence_mode_v1_descriptive_no_update" BEFORE UPDATE ON "r_occurrence_mode_v1_descriptive" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_occurrence_mode_v1_descriptive_no_delete" BEFORE DELETE ON "r_occurrence_mode_v1_descriptive" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_action_no_update" BEFORE UPDATE ON "r_payload_v24_action" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_action_no_delete" BEFORE DELETE ON "r_payload_v24_action" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_worlds_no_update" BEFORE UPDATE ON "r_payload_v24_worlds" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_worlds_no_delete" BEFORE DELETE ON "r_payload_v24_worlds" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_worlds_items_no_update" BEFORE UPDATE ON "r_payload_v24_worlds_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_worlds_items_no_delete" BEFORE DELETE ON "r_payload_v24_worlds_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_region_no_update" BEFORE UPDATE ON "r_payload_v24_region" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_region_no_delete" BEFORE DELETE ON "r_payload_v24_region" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_sequence_no_update" BEFORE UPDATE ON "r_payload_v24_sequence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_sequence_no_delete" BEFORE DELETE ON "r_payload_v24_sequence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_occurrence_id_no_update" BEFORE UPDATE ON "r_payload_v24_occurrence_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_occurrence_id_no_delete" BEFORE DELETE ON "r_payload_v24_occurrence_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_participants_no_update" BEFORE UPDATE ON "r_payload_v24_participants" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_participants_no_delete" BEFORE DELETE ON "r_payload_v24_participants" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_participants_items_no_update" BEFORE UPDATE ON "r_payload_v24_participants_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_participants_items_no_delete" BEFORE DELETE ON "r_payload_v24_participants_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_participant_no_update" BEFORE UPDATE ON "r_event_participant" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_participant_no_delete" BEFORE DELETE ON "r_event_participant" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_preconditions_no_update" BEFORE UPDATE ON "r_payload_v24_preconditions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_preconditions_no_delete" BEFORE DELETE ON "r_payload_v24_preconditions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_preconditions_items_no_update" BEFORE UPDATE ON "r_payload_v24_preconditions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_preconditions_items_no_delete" BEFORE DELETE ON "r_payload_v24_preconditions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_effects_no_update" BEFORE UPDATE ON "r_payload_v24_effects" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_effects_no_delete" BEFORE DELETE ON "r_payload_v24_effects" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_effects_items_no_update" BEFORE UPDATE ON "r_payload_v24_effects_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_effects_items_no_delete" BEFORE DELETE ON "r_payload_v24_effects_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_effect_no_update" BEFORE UPDATE ON "r_entity_effect" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_effect_no_delete" BEFORE DELETE ON "r_entity_effect" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_labels_no_update" BEFORE UPDATE ON "r_payload_v24_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_labels_no_delete" BEFORE DELETE ON "r_payload_v24_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_labels_items_no_update" BEFORE UPDATE ON "r_payload_v24_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_labels_items_no_delete" BEFORE DELETE ON "r_payload_v24_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_expansion_version_no_update" BEFORE UPDATE ON "r_payload_v24_expansion_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v24_expansion_version_no_delete" BEFORE DELETE ON "r_payload_v24_expansion_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v25_no_update" BEFORE UPDATE ON "r_payload_v25" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v25_no_delete" BEFORE DELETE ON "r_payload_v25" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_no_update" BEFORE UPDATE ON "r_payload_v26" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_no_delete" BEFORE DELETE ON "r_payload_v26" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_labels_no_update" BEFORE UPDATE ON "r_payload_v26_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_labels_no_delete" BEFORE DELETE ON "r_payload_v26_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_labels_items_no_update" BEFORE UPDATE ON "r_payload_v26_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_labels_items_no_delete" BEFORE DELETE ON "r_payload_v26_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_requirements_no_update" BEFORE UPDATE ON "r_payload_v26_requirements" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_requirements_no_delete" BEFORE DELETE ON "r_payload_v26_requirements" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_requirements_items_no_update" BEFORE UPDATE ON "r_payload_v26_requirements_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v26_requirements_items_no_delete" BEFORE DELETE ON "r_payload_v26_requirements_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_attribute_requirement_no_update" BEFORE UPDATE ON "r_attribute_requirement" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_attribute_requirement_no_delete" BEFORE DELETE ON "r_attribute_requirement" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_consequence_contract_no_update" BEFORE UPDATE ON "r_consequence_contract" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_consequence_contract_no_delete" BEFORE DELETE ON "r_consequence_contract" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_consequence_contract_slots_no_update" BEFORE UPDATE ON "r_consequence_contract_slots" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_consequence_contract_slots_no_delete" BEFORE DELETE ON "r_consequence_contract_slots" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_consequence_contract_slots_items_no_update" BEFORE UPDATE ON "r_consequence_contract_slots_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_consequence_contract_slots_items_no_delete" BEFORE DELETE ON "r_consequence_contract_slots_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_slot_no_update" BEFORE UPDATE ON "r_effect_slot" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_slot_no_delete" BEFORE DELETE ON "r_effect_slot" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_target_no_update" BEFORE UPDATE ON "r_effect_target" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_target_no_delete" BEFORE DELETE ON "r_effect_target" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_condition_no_update" BEFORE UPDATE ON "r_effect_condition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_condition_no_delete" BEFORE DELETE ON "r_effect_condition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_condition_v0_no_update" BEFORE UPDATE ON "r_effect_condition_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_condition_v0_no_delete" BEFORE DELETE ON "r_effect_condition_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_condition_v1_no_update" BEFORE UPDATE ON "r_effect_condition_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_condition_v1_no_delete" BEFORE DELETE ON "r_effect_condition_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_change_no_update" BEFORE UPDATE ON "r_effect_change" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_change_no_delete" BEFORE DELETE ON "r_effect_change" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_change_v0_no_update" BEFORE UPDATE ON "r_effect_change_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_change_v0_no_delete" BEFORE DELETE ON "r_effect_change_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_change_v1_no_update" BEFORE UPDATE ON "r_effect_change_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_change_v1_no_delete" BEFORE DELETE ON "r_effect_change_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_change_v1_unit_no_update" BEFORE UPDATE ON "r_effect_change_v1_unit" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_change_v1_unit_no_delete" BEFORE DELETE ON "r_effect_change_v1_unit" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_lifetime_no_update" BEFORE UPDATE ON "r_effect_lifetime" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_lifetime_no_delete" BEFORE DELETE ON "r_effect_lifetime" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_lifetime_v0_no_update" BEFORE UPDATE ON "r_effect_lifetime_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_lifetime_v0_no_delete" BEFORE DELETE ON "r_effect_lifetime_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_lifetime_v1_no_update" BEFORE UPDATE ON "r_effect_lifetime_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_effect_lifetime_v1_no_delete" BEFORE DELETE ON "r_effect_lifetime_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v27_no_update" BEFORE UPDATE ON "r_payload_v27" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v27_no_delete" BEFORE DELETE ON "r_payload_v27" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v27_acquisition_no_update" BEFORE UPDATE ON "r_payload_v27_acquisition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v27_acquisition_no_delete" BEFORE DELETE ON "r_payload_v27_acquisition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_acquisition_no_update" BEFORE UPDATE ON "r_knowledge_acquisition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_acquisition_no_delete" BEFORE DELETE ON "r_knowledge_acquisition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_acquisition_world_no_update" BEFORE UPDATE ON "r_knowledge_acquisition_world" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_acquisition_world_no_delete" BEFORE DELETE ON "r_knowledge_acquisition_world" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_basis_no_update" BEFORE UPDATE ON "r_knowledge_basis" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_basis_no_delete" BEFORE DELETE ON "r_knowledge_basis" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_basis_v0_no_update" BEFORE UPDATE ON "r_knowledge_basis_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_basis_v0_no_delete" BEFORE DELETE ON "r_knowledge_basis_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_basis_v1_no_update" BEFORE UPDATE ON "r_knowledge_basis_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_basis_v1_no_delete" BEFORE DELETE ON "r_knowledge_basis_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_basis_v1_interpretation_no_update" BEFORE UPDATE ON "r_knowledge_basis_v1_interpretation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_knowledge_basis_v1_interpretation_no_delete" BEFORE DELETE ON "r_knowledge_basis_v1_interpretation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v27_certainty_no_update" BEFORE UPDATE ON "r_payload_v27_certainty" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v27_certainty_no_delete" BEFORE DELETE ON "r_payload_v27_certainty" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v28_no_update" BEFORE UPDATE ON "r_payload_v28" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v28_no_delete" BEFORE DELETE ON "r_payload_v28" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v28_interpretation_no_update" BEFORE UPDATE ON "r_payload_v28_interpretation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v28_interpretation_no_delete" BEFORE DELETE ON "r_payload_v28_interpretation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_no_update" BEFORE UPDATE ON "r_payload_v29" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_no_delete" BEFORE DELETE ON "r_payload_v29" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_intended_recipients_no_update" BEFORE UPDATE ON "r_payload_v29_intended_recipients" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_intended_recipients_no_delete" BEFORE DELETE ON "r_payload_v29_intended_recipients" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_intended_recipients_items_no_update" BEFORE UPDATE ON "r_payload_v29_intended_recipients_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_intended_recipients_items_no_delete" BEFORE DELETE ON "r_payload_v29_intended_recipients_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_actual_recipients_no_update" BEFORE UPDATE ON "r_payload_v29_actual_recipients" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_actual_recipients_no_delete" BEFORE DELETE ON "r_payload_v29_actual_recipients" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_actual_recipients_items_no_update" BEFORE UPDATE ON "r_payload_v29_actual_recipients_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_actual_recipients_items_no_delete" BEFORE DELETE ON "r_payload_v29_actual_recipients_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_content_no_update" BEFORE UPDATE ON "r_payload_v29_content" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_content_no_delete" BEFORE DELETE ON "r_payload_v29_content" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_content_items_no_update" BEFORE UPDATE ON "r_payload_v29_content_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_content_items_no_delete" BEFORE DELETE ON "r_payload_v29_content_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_channel_no_update" BEFORE UPDATE ON "r_payload_v29_channel" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_channel_no_delete" BEFORE DELETE ON "r_payload_v29_channel" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_received_at_no_update" BEFORE UPDATE ON "r_payload_v29_received_at" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v29_received_at_no_delete" BEFORE DELETE ON "r_payload_v29_received_at" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v30_no_update" BEFORE UPDATE ON "r_payload_v30" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v30_no_delete" BEFORE DELETE ON "r_payload_v30" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v30_alleged_no_update" BEFORE UPDATE ON "r_payload_v30_alleged" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v30_alleged_no_delete" BEFORE DELETE ON "r_payload_v30_alleged" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_no_update" BEFORE UPDATE ON "r_payload_v31" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_no_delete" BEFORE DELETE ON "r_payload_v31" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_scope_no_update" BEFORE UPDATE ON "r_payload_v31_scope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_scope_no_delete" BEFORE DELETE ON "r_payload_v31_scope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_scope_items_no_update" BEFORE UPDATE ON "r_payload_v31_scope_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_scope_items_no_delete" BEFORE DELETE ON "r_payload_v31_scope_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_fictional_knowers_no_update" BEFORE UPDATE ON "r_payload_v31_fictional_knowers" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_fictional_knowers_no_delete" BEFORE DELETE ON "r_payload_v31_fictional_knowers" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_fictional_knowers_items_no_update" BEFORE UPDATE ON "r_payload_v31_fictional_knowers_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_fictional_knowers_items_no_delete" BEFORE DELETE ON "r_payload_v31_fictional_knowers_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_concealment_no_update" BEFORE UPDATE ON "r_payload_v31_concealment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v31_concealment_no_delete" BEFORE DELETE ON "r_payload_v31_concealment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_no_update" BEFORE UPDATE ON "r_payload_v32" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_no_delete" BEFORE DELETE ON "r_payload_v32" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_desired_no_update" BEFORE UPDATE ON "r_payload_v32_desired" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_desired_no_delete" BEFORE DELETE ON "r_payload_v32_desired" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_prerequisites_no_update" BEFORE UPDATE ON "r_payload_v32_prerequisites" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_prerequisites_no_delete" BEFORE DELETE ON "r_payload_v32_prerequisites" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_prerequisites_items_no_update" BEFORE UPDATE ON "r_payload_v32_prerequisites_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_prerequisites_items_no_delete" BEFORE DELETE ON "r_payload_v32_prerequisites_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_steps_no_update" BEFORE UPDATE ON "r_payload_v32_steps" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_steps_no_delete" BEFORE DELETE ON "r_payload_v32_steps" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_steps_items_no_update" BEFORE UPDATE ON "r_payload_v32_steps_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v32_steps_items_no_delete" BEFORE DELETE ON "r_payload_v32_steps_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_no_update" BEFORE UPDATE ON "r_payload_v33" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_no_delete" BEFORE DELETE ON "r_payload_v33" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_parties_no_update" BEFORE UPDATE ON "r_payload_v33_parties" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_parties_no_delete" BEFORE DELETE ON "r_payload_v33_parties" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_parties_items_no_update" BEFORE UPDATE ON "r_payload_v33_parties_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_parties_items_no_delete" BEFORE DELETE ON "r_payload_v33_parties_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_party_no_update" BEFORE UPDATE ON "r_commitment_party" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_party_no_delete" BEFORE DELETE ON "r_commitment_party" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_conditions_no_update" BEFORE UPDATE ON "r_payload_v33_conditions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_conditions_no_delete" BEFORE DELETE ON "r_payload_v33_conditions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_conditions_items_no_update" BEFORE UPDATE ON "r_payload_v33_conditions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_conditions_items_no_delete" BEFORE DELETE ON "r_payload_v33_conditions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_deadline_no_update" BEFORE UPDATE ON "r_payload_v33_deadline" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v33_deadline_no_delete" BEFORE DELETE ON "r_payload_v33_deadline" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v34_no_update" BEFORE UPDATE ON "r_payload_v34" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v34_no_delete" BEFORE DELETE ON "r_payload_v34" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v34_external_id_no_update" BEFORE UPDATE ON "r_payload_v34_external_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v34_external_id_no_delete" BEFORE DELETE ON "r_payload_v34_external_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_origin_metadata_no_update" BEFORE UPDATE ON "r_origin_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_origin_metadata_no_delete" BEFORE DELETE ON "r_origin_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_origin_metadata_externally_asserted_author_no_update" BEFORE UPDATE ON "r_origin_metadata_externally_asserted_author" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_origin_metadata_externally_asserted_author_no_delete" BEFORE DELETE ON "r_origin_metadata_externally_asserted_author" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_origin_metadata_origin_note_no_update" BEFORE UPDATE ON "r_origin_metadata_origin_note" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_origin_metadata_origin_note_no_delete" BEFORE DELETE ON "r_origin_metadata_origin_note" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v34_versions_no_update" BEFORE UPDATE ON "r_payload_v34_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v34_versions_no_delete" BEFORE DELETE ON "r_payload_v34_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v34_versions_items_no_update" BEFORE UPDATE ON "r_payload_v34_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v34_versions_items_no_delete" BEFORE DELETE ON "r_payload_v34_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v35_no_update" BEFORE UPDATE ON "r_payload_v35" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v35_no_delete" BEFORE DELETE ON "r_payload_v35" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_decoding_descriptor_no_update" BEFORE UPDATE ON "r_decoding_descriptor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_decoding_descriptor_no_delete" BEFORE DELETE ON "r_decoding_descriptor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v36_no_update" BEFORE UPDATE ON "r_payload_v36" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v36_no_delete" BEFORE DELETE ON "r_payload_v36" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_no_update" BEFORE UPDATE ON "r_anchor_locator" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_no_delete" BEFORE DELETE ON "r_anchor_locator" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_v0_no_update" BEFORE UPDATE ON "r_anchor_locator_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_v0_no_delete" BEFORE DELETE ON "r_anchor_locator_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_v1_no_update" BEFORE UPDATE ON "r_anchor_locator_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_v1_no_delete" BEFORE DELETE ON "r_anchor_locator_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_v1_path_no_update" BEFORE UPDATE ON "r_anchor_locator_v1_path" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_v1_path_no_delete" BEFORE DELETE ON "r_anchor_locator_v1_path" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_v1_path_items_no_update" BEFORE UPDATE ON "r_anchor_locator_v1_path_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_locator_v1_path_items_no_delete" BEFORE DELETE ON "r_anchor_locator_v1_path_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v36_context_no_update" BEFORE UPDATE ON "r_payload_v36_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v36_context_no_delete" BEFORE DELETE ON "r_payload_v36_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v37_no_update" BEFORE UPDATE ON "r_payload_v37" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v37_no_delete" BEFORE DELETE ON "r_payload_v37" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v37_fingerprints_no_update" BEFORE UPDATE ON "r_payload_v37_fingerprints" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v37_fingerprints_no_delete" BEFORE DELETE ON "r_payload_v37_fingerprints" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v37_fingerprints_items_no_update" BEFORE UPDATE ON "r_payload_v37_fingerprints_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_payload_v37_fingerprints_items_no_delete" BEFORE DELETE ON "r_payload_v37_fingerprints_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_issue_decision_mode_no_update" BEFORE UPDATE ON "r_issue_decision_mode" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_issue_decision_mode_no_delete" BEFORE DELETE ON "r_issue_decision_mode" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_no_update" BEFORE UPDATE ON "r_domain_operation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_no_delete" BEFORE DELETE ON "r_domain_operation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v0_no_update" BEFORE UPDATE ON "r_domain_operation_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v0_no_delete" BEFORE DELETE ON "r_domain_operation_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_no_update" BEFORE UPDATE ON "r_appearance" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_no_delete" BEFORE DELETE ON "r_appearance" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_images_no_update" BEFORE UPDATE ON "r_appearance_images" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_images_no_delete" BEFORE DELETE ON "r_appearance_images" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_images_items_no_update" BEFORE UPDATE ON "r_appearance_images_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_images_items_no_delete" BEFORE DELETE ON "r_appearance_images_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_links_no_update" BEFORE UPDATE ON "r_appearance_links" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_links_no_delete" BEFORE DELETE ON "r_appearance_links" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_links_items_no_update" BEFORE UPDATE ON "r_appearance_links_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_appearance_links_items_no_delete" BEFORE DELETE ON "r_appearance_links_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v1_no_update" BEFORE UPDATE ON "r_domain_operation_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v1_no_delete" BEFORE DELETE ON "r_domain_operation_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v2_no_update" BEFORE UPDATE ON "r_domain_operation_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v2_no_delete" BEFORE DELETE ON "r_domain_operation_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_image_asset_no_update" BEFORE UPDATE ON "r_image_asset" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_image_asset_no_delete" BEFORE DELETE ON "r_image_asset" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v3_no_update" BEFORE UPDATE ON "r_domain_operation_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v3_no_delete" BEFORE DELETE ON "r_domain_operation_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v4_no_update" BEFORE UPDATE ON "r_domain_operation_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v4_no_delete" BEFORE DELETE ON "r_domain_operation_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_no_update" BEFORE UPDATE ON "r_entity" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_no_delete" BEFORE DELETE ON "r_entity" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_names_no_update" BEFORE UPDATE ON "r_entity_names" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_names_no_delete" BEFORE DELETE ON "r_entity_names" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_names_items_no_update" BEFORE UPDATE ON "r_entity_names_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_names_items_no_delete" BEFORE DELETE ON "r_entity_names_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_classification_no_update" BEFORE UPDATE ON "r_entity_classification" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_classification_no_delete" BEFORE DELETE ON "r_entity_classification" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_world_associations_no_update" BEFORE UPDATE ON "r_entity_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_world_associations_no_delete" BEFORE DELETE ON "r_entity_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_world_associations_items_no_update" BEFORE UPDATE ON "r_entity_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_world_associations_items_no_delete" BEFORE DELETE ON "r_entity_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_labels_no_update" BEFORE UPDATE ON "r_entity_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_labels_no_delete" BEFORE DELETE ON "r_entity_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_labels_items_no_update" BEFORE UPDATE ON "r_entity_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_labels_items_no_delete" BEFORE DELETE ON "r_entity_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_metadata_no_update" BEFORE UPDATE ON "r_entity_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_metadata_no_delete" BEFORE DELETE ON "r_entity_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_metadata_items_no_update" BEFORE UPDATE ON "r_entity_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_metadata_items_no_delete" BEFORE DELETE ON "r_entity_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v5_no_update" BEFORE UPDATE ON "r_domain_operation_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v5_no_delete" BEFORE DELETE ON "r_domain_operation_v5" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v6_no_update" BEFORE UPDATE ON "r_domain_operation_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v6_no_delete" BEFORE DELETE ON "r_domain_operation_v6" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v7_no_update" BEFORE UPDATE ON "r_domain_operation_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v7_no_delete" BEFORE DELETE ON "r_domain_operation_v7" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_no_update" BEFORE UPDATE ON "r_world" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_no_delete" BEFORE DELETE ON "r_world" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_aliases_no_update" BEFORE UPDATE ON "r_world_aliases" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_aliases_no_delete" BEFORE DELETE ON "r_world_aliases" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_aliases_items_no_update" BEFORE UPDATE ON "r_world_aliases_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_aliases_items_no_delete" BEFORE DELETE ON "r_world_aliases_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_setting_type_no_update" BEFORE UPDATE ON "r_world_setting_type" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_setting_type_no_delete" BEFORE DELETE ON "r_world_setting_type" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_labels_no_update" BEFORE UPDATE ON "r_world_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_labels_no_delete" BEFORE DELETE ON "r_world_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_labels_items_no_update" BEFORE UPDATE ON "r_world_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_labels_items_no_delete" BEFORE DELETE ON "r_world_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_metadata_no_update" BEFORE UPDATE ON "r_world_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_metadata_no_delete" BEFORE DELETE ON "r_world_metadata" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_metadata_items_no_update" BEFORE UPDATE ON "r_world_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_world_metadata_items_no_delete" BEFORE DELETE ON "r_world_metadata_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v8_no_update" BEFORE UPDATE ON "r_domain_operation_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v8_no_delete" BEFORE DELETE ON "r_domain_operation_v8" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v9_no_update" BEFORE UPDATE ON "r_domain_operation_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v9_no_delete" BEFORE DELETE ON "r_domain_operation_v9" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v10_no_update" BEFORE UPDATE ON "r_domain_operation_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v10_no_delete" BEFORE DELETE ON "r_domain_operation_v10" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_no_update" BEFORE UPDATE ON "r_work" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_no_delete" BEFORE DELETE ON "r_work" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_labels_no_update" BEFORE UPDATE ON "r_work_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_labels_no_delete" BEFORE DELETE ON "r_work_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_labels_items_no_update" BEFORE UPDATE ON "r_work_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_labels_items_no_delete" BEFORE DELETE ON "r_work_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_source_refs_no_update" BEFORE UPDATE ON "r_work_source_refs" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_source_refs_no_delete" BEFORE DELETE ON "r_work_source_refs" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_source_refs_items_no_update" BEFORE UPDATE ON "r_work_source_refs_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_source_refs_items_no_delete" BEFORE DELETE ON "r_work_source_refs_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_versions_no_update" BEFORE UPDATE ON "r_work_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_versions_no_delete" BEFORE DELETE ON "r_work_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_versions_items_no_update" BEFORE UPDATE ON "r_work_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_versions_items_no_delete" BEFORE DELETE ON "r_work_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_world_associations_no_update" BEFORE UPDATE ON "r_work_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_world_associations_no_delete" BEFORE DELETE ON "r_work_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_world_associations_items_no_update" BEFORE UPDATE ON "r_work_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_work_world_associations_items_no_delete" BEFORE DELETE ON "r_work_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v11_no_update" BEFORE UPDATE ON "r_domain_operation_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v11_no_delete" BEFORE DELETE ON "r_domain_operation_v11" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_no_update" BEFORE UPDATE ON "r_saga" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_no_delete" BEFORE DELETE ON "r_saga" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_labels_no_update" BEFORE UPDATE ON "r_saga_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_labels_no_delete" BEFORE DELETE ON "r_saga_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_labels_items_no_update" BEFORE UPDATE ON "r_saga_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_labels_items_no_delete" BEFORE DELETE ON "r_saga_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_memberships_no_update" BEFORE UPDATE ON "r_saga_memberships" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_memberships_no_delete" BEFORE DELETE ON "r_saga_memberships" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_memberships_items_no_update" BEFORE UPDATE ON "r_saga_memberships_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saga_memberships_items_no_delete" BEFORE DELETE ON "r_saga_memberships_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v12_no_update" BEFORE UPDATE ON "r_domain_operation_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v12_no_delete" BEFORE DELETE ON "r_domain_operation_v12" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v13_no_update" BEFORE UPDATE ON "r_domain_operation_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v13_no_delete" BEFORE DELETE ON "r_domain_operation_v13" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v14_no_update" BEFORE UPDATE ON "r_domain_operation_v14" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v14_no_delete" BEFORE DELETE ON "r_domain_operation_v14" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v15_no_update" BEFORE UPDATE ON "r_domain_operation_v15" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v15_no_delete" BEFORE DELETE ON "r_domain_operation_v15" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_no_update" BEFORE UPDATE ON "r_proposition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_no_delete" BEFORE DELETE ON "r_proposition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_roles_no_update" BEFORE UPDATE ON "r_proposition_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_roles_no_delete" BEFORE DELETE ON "r_proposition_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_roles_items_no_update" BEFORE UPDATE ON "r_proposition_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_roles_items_no_delete" BEFORE DELETE ON "r_proposition_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_value_no_update" BEFORE UPDATE ON "r_proposition_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposition_value_no_delete" BEFORE DELETE ON "r_proposition_value" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assertion_no_update" BEFORE UPDATE ON "r_assertion" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assertion_no_delete" BEFORE DELETE ON "r_assertion" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assertion_alternatives_no_update" BEFORE UPDATE ON "r_assertion_alternatives" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assertion_alternatives_no_delete" BEFORE DELETE ON "r_assertion_alternatives" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assertion_alternatives_items_no_update" BEFORE UPDATE ON "r_assertion_alternatives_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assertion_alternatives_items_no_delete" BEFORE DELETE ON "r_assertion_alternatives_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assertion_established_by_no_update" BEFORE UPDATE ON "r_assertion_established_by" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assertion_established_by_no_delete" BEFORE DELETE ON "r_assertion_established_by" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v16_no_update" BEFORE UPDATE ON "r_domain_operation_v16" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v16_no_delete" BEFORE DELETE ON "r_domain_operation_v16" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v17_no_update" BEFORE UPDATE ON "r_domain_operation_v17" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v17_no_delete" BEFORE DELETE ON "r_domain_operation_v17" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v18_no_update" BEFORE UPDATE ON "r_domain_operation_v18" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v18_no_delete" BEFORE DELETE ON "r_domain_operation_v18" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v19_no_update" BEFORE UPDATE ON "r_domain_operation_v19" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v19_no_delete" BEFORE DELETE ON "r_domain_operation_v19" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v20_no_update" BEFORE UPDATE ON "r_domain_operation_v20" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v20_no_delete" BEFORE DELETE ON "r_domain_operation_v20" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v21_no_update" BEFORE UPDATE ON "r_domain_operation_v21" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v21_no_delete" BEFORE DELETE ON "r_domain_operation_v21" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_item_power_no_update" BEFORE UPDATE ON "r_item_power" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_item_power_no_delete" BEFORE DELETE ON "r_item_power" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v22_no_update" BEFORE UPDATE ON "r_domain_operation_v22" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v22_no_delete" BEFORE DELETE ON "r_domain_operation_v22" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_no_update" BEFORE UPDATE ON "r_action_definition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_no_delete" BEFORE DELETE ON "r_action_definition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_labels_no_update" BEFORE UPDATE ON "r_action_definition_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_labels_no_delete" BEFORE DELETE ON "r_action_definition_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_labels_items_no_update" BEFORE UPDATE ON "r_action_definition_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_labels_items_no_delete" BEFORE DELETE ON "r_action_definition_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_requirements_no_update" BEFORE UPDATE ON "r_action_definition_requirements" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_requirements_no_delete" BEFORE DELETE ON "r_action_definition_requirements" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_requirements_items_no_update" BEFORE UPDATE ON "r_action_definition_requirements_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_action_definition_requirements_items_no_delete" BEFORE DELETE ON "r_action_definition_requirements_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v23_no_update" BEFORE UPDATE ON "r_domain_operation_v23" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v23_no_delete" BEFORE DELETE ON "r_domain_operation_v23" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_no_update" BEFORE UPDATE ON "r_event" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_no_delete" BEFORE DELETE ON "r_event" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_action_no_update" BEFORE UPDATE ON "r_event_action" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_action_no_delete" BEFORE DELETE ON "r_event_action" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_worlds_no_update" BEFORE UPDATE ON "r_event_worlds" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_worlds_no_delete" BEFORE DELETE ON "r_event_worlds" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_worlds_items_no_update" BEFORE UPDATE ON "r_event_worlds_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_worlds_items_no_delete" BEFORE DELETE ON "r_event_worlds_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_region_no_update" BEFORE UPDATE ON "r_event_region" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_region_no_delete" BEFORE DELETE ON "r_event_region" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_sequence_no_update" BEFORE UPDATE ON "r_event_sequence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_sequence_no_delete" BEFORE DELETE ON "r_event_sequence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_occurrence_id_no_update" BEFORE UPDATE ON "r_event_occurrence_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_occurrence_id_no_delete" BEFORE DELETE ON "r_event_occurrence_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_participants_no_update" BEFORE UPDATE ON "r_event_participants" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_participants_no_delete" BEFORE DELETE ON "r_event_participants" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_participants_items_no_update" BEFORE UPDATE ON "r_event_participants_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_participants_items_no_delete" BEFORE DELETE ON "r_event_participants_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_preconditions_no_update" BEFORE UPDATE ON "r_event_preconditions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_preconditions_no_delete" BEFORE DELETE ON "r_event_preconditions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_preconditions_items_no_update" BEFORE UPDATE ON "r_event_preconditions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_preconditions_items_no_delete" BEFORE DELETE ON "r_event_preconditions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_effects_no_update" BEFORE UPDATE ON "r_event_effects" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_effects_no_delete" BEFORE DELETE ON "r_event_effects" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_effects_items_no_update" BEFORE UPDATE ON "r_event_effects_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_effects_items_no_delete" BEFORE DELETE ON "r_event_effects_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_labels_no_update" BEFORE UPDATE ON "r_event_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_labels_no_delete" BEFORE DELETE ON "r_event_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_labels_items_no_update" BEFORE UPDATE ON "r_event_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_labels_items_no_delete" BEFORE DELETE ON "r_event_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_expansion_version_no_update" BEFORE UPDATE ON "r_event_expansion_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_expansion_version_no_delete" BEFORE DELETE ON "r_event_expansion_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v24_no_update" BEFORE UPDATE ON "r_domain_operation_v24" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v24_no_delete" BEFORE DELETE ON "r_domain_operation_v24" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v25_no_update" BEFORE UPDATE ON "r_domain_operation_v25" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v25_no_delete" BEFORE DELETE ON "r_domain_operation_v25" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_epistemic_attitude_no_update" BEFORE UPDATE ON "r_epistemic_attitude" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_epistemic_attitude_no_delete" BEFORE DELETE ON "r_epistemic_attitude" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_epistemic_attitude_acquisition_no_update" BEFORE UPDATE ON "r_epistemic_attitude_acquisition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_epistemic_attitude_acquisition_no_delete" BEFORE DELETE ON "r_epistemic_attitude_acquisition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_epistemic_attitude_certainty_no_update" BEFORE UPDATE ON "r_epistemic_attitude_certainty" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_epistemic_attitude_certainty_no_delete" BEFORE DELETE ON "r_epistemic_attitude_certainty" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v26_no_update" BEFORE UPDATE ON "r_domain_operation_v26" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v26_no_delete" BEFORE DELETE ON "r_domain_operation_v26" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_observation_no_update" BEFORE UPDATE ON "r_observation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_observation_no_delete" BEFORE DELETE ON "r_observation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_observation_interpretation_no_update" BEFORE UPDATE ON "r_observation_interpretation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_observation_interpretation_no_delete" BEFORE DELETE ON "r_observation_interpretation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v27_no_update" BEFORE UPDATE ON "r_domain_operation_v27" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v27_no_delete" BEFORE DELETE ON "r_domain_operation_v27" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_no_update" BEFORE UPDATE ON "r_communication" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_no_delete" BEFORE DELETE ON "r_communication" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_intended_recipients_no_update" BEFORE UPDATE ON "r_communication_intended_recipients" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_intended_recipients_no_delete" BEFORE DELETE ON "r_communication_intended_recipients" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_intended_recipients_items_no_update" BEFORE UPDATE ON "r_communication_intended_recipients_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_intended_recipients_items_no_delete" BEFORE DELETE ON "r_communication_intended_recipients_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_actual_recipients_no_update" BEFORE UPDATE ON "r_communication_actual_recipients" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_actual_recipients_no_delete" BEFORE DELETE ON "r_communication_actual_recipients" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_actual_recipients_items_no_update" BEFORE UPDATE ON "r_communication_actual_recipients_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_actual_recipients_items_no_delete" BEFORE DELETE ON "r_communication_actual_recipients_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_content_no_update" BEFORE UPDATE ON "r_communication_content" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_content_no_delete" BEFORE DELETE ON "r_communication_content" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_content_items_no_update" BEFORE UPDATE ON "r_communication_content_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_content_items_no_delete" BEFORE DELETE ON "r_communication_content_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_channel_no_update" BEFORE UPDATE ON "r_communication_channel" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_channel_no_delete" BEFORE DELETE ON "r_communication_channel" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_received_at_no_update" BEFORE UPDATE ON "r_communication_received_at" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_communication_received_at_no_delete" BEFORE DELETE ON "r_communication_received_at" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v28_no_update" BEFORE UPDATE ON "r_domain_operation_v28" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v28_no_delete" BEFORE DELETE ON "r_domain_operation_v28" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_memory_no_update" BEFORE UPDATE ON "r_memory" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_memory_no_delete" BEFORE DELETE ON "r_memory" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_memory_alleged_no_update" BEFORE UPDATE ON "r_memory_alleged" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_memory_alleged_no_delete" BEFORE DELETE ON "r_memory_alleged" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v29_no_update" BEFORE UPDATE ON "r_domain_operation_v29" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v29_no_delete" BEFORE DELETE ON "r_domain_operation_v29" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_no_update" BEFORE UPDATE ON "r_goal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_no_delete" BEFORE DELETE ON "r_goal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_desired_no_update" BEFORE UPDATE ON "r_goal_desired" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_desired_no_delete" BEFORE DELETE ON "r_goal_desired" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_prerequisites_no_update" BEFORE UPDATE ON "r_goal_prerequisites" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_prerequisites_no_delete" BEFORE DELETE ON "r_goal_prerequisites" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_prerequisites_items_no_update" BEFORE UPDATE ON "r_goal_prerequisites_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_prerequisites_items_no_delete" BEFORE DELETE ON "r_goal_prerequisites_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_steps_no_update" BEFORE UPDATE ON "r_goal_steps" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_steps_no_delete" BEFORE DELETE ON "r_goal_steps" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_steps_items_no_update" BEFORE UPDATE ON "r_goal_steps_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_goal_steps_items_no_delete" BEFORE DELETE ON "r_goal_steps_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v30_no_update" BEFORE UPDATE ON "r_domain_operation_v30" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v30_no_delete" BEFORE DELETE ON "r_domain_operation_v30" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_no_update" BEFORE UPDATE ON "r_commitment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_no_delete" BEFORE DELETE ON "r_commitment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_parties_no_update" BEFORE UPDATE ON "r_commitment_parties" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_parties_no_delete" BEFORE DELETE ON "r_commitment_parties" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_parties_items_no_update" BEFORE UPDATE ON "r_commitment_parties_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_parties_items_no_delete" BEFORE DELETE ON "r_commitment_parties_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_conditions_no_update" BEFORE UPDATE ON "r_commitment_conditions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_conditions_no_delete" BEFORE DELETE ON "r_commitment_conditions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_conditions_items_no_update" BEFORE UPDATE ON "r_commitment_conditions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_conditions_items_no_delete" BEFORE DELETE ON "r_commitment_conditions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_deadline_no_update" BEFORE UPDATE ON "r_commitment_deadline" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commitment_deadline_no_delete" BEFORE DELETE ON "r_commitment_deadline" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v31_no_update" BEFORE UPDATE ON "r_domain_operation_v31" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v31_no_delete" BEFORE DELETE ON "r_domain_operation_v31" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_type_no_update" BEFORE UPDATE ON "r_entity_type" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_type_no_delete" BEFORE DELETE ON "r_entity_type" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_type_labels_no_update" BEFORE UPDATE ON "r_entity_type_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_type_labels_no_delete" BEFORE DELETE ON "r_entity_type_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_type_labels_items_no_update" BEFORE UPDATE ON "r_entity_type_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_type_labels_items_no_delete" BEFORE DELETE ON "r_entity_type_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_type_parent_no_update" BEFORE UPDATE ON "r_entity_type_parent" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_entity_type_parent_no_delete" BEFORE DELETE ON "r_entity_type_parent" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v32_no_update" BEFORE UPDATE ON "r_domain_operation_v32" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v32_no_delete" BEFORE DELETE ON "r_domain_operation_v32" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_no_update" BEFORE UPDATE ON "r_property_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_no_delete" BEFORE DELETE ON "r_property_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_labels_no_update" BEFORE UPDATE ON "r_property_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_labels_no_delete" BEFORE DELETE ON "r_property_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_labels_items_no_update" BEFORE UPDATE ON "r_property_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_labels_items_no_delete" BEFORE DELETE ON "r_property_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_subject_types_no_update" BEFORE UPDATE ON "r_property_def_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_subject_types_no_delete" BEFORE DELETE ON "r_property_def_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_subject_types_items_no_update" BEFORE UPDATE ON "r_property_def_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_subject_types_items_no_delete" BEFORE DELETE ON "r_property_def_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_unit_dimension_no_update" BEFORE UPDATE ON "r_property_def_unit_dimension" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_unit_dimension_no_delete" BEFORE DELETE ON "r_property_def_unit_dimension" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_inverse_no_update" BEFORE UPDATE ON "r_property_def_inverse" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_property_def_inverse_no_delete" BEFORE DELETE ON "r_property_def_inverse" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v33_no_update" BEFORE UPDATE ON "r_domain_operation_v33" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v33_no_delete" BEFORE DELETE ON "r_domain_operation_v33" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_no_update" BEFORE UPDATE ON "r_relation_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_no_delete" BEFORE DELETE ON "r_relation_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_labels_no_update" BEFORE UPDATE ON "r_relation_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_labels_no_delete" BEFORE DELETE ON "r_relation_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_labels_items_no_update" BEFORE UPDATE ON "r_relation_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_labels_items_no_delete" BEFORE DELETE ON "r_relation_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_roles_no_update" BEFORE UPDATE ON "r_relation_def_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_roles_no_delete" BEFORE DELETE ON "r_relation_def_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_roles_items_no_update" BEFORE UPDATE ON "r_relation_def_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_relation_def_roles_items_no_delete" BEFORE DELETE ON "r_relation_def_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v34_no_update" BEFORE UPDATE ON "r_domain_operation_v34" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v34_no_delete" BEFORE DELETE ON "r_domain_operation_v34" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_no_update" BEFORE UPDATE ON "r_unit_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_no_delete" BEFORE DELETE ON "r_unit_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_labels_no_update" BEFORE UPDATE ON "r_unit_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_labels_no_delete" BEFORE DELETE ON "r_unit_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_labels_items_no_update" BEFORE UPDATE ON "r_unit_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_labels_items_no_delete" BEFORE DELETE ON "r_unit_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_scale_to_base_no_update" BEFORE UPDATE ON "r_unit_def_scale_to_base" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_scale_to_base_no_delete" BEFORE DELETE ON "r_unit_def_scale_to_base" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_base_no_update" BEFORE UPDATE ON "r_unit_def_base" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unit_def_base_no_delete" BEFORE DELETE ON "r_unit_def_base" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v35_no_update" BEFORE UPDATE ON "r_domain_operation_v35" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v35_no_delete" BEFORE DELETE ON "r_domain_operation_v35" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_no_update" BEFORE UPDATE ON "r_calendar_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_no_delete" BEFORE DELETE ON "r_calendar_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_labels_no_update" BEFORE UPDATE ON "r_calendar_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_labels_no_delete" BEFORE DELETE ON "r_calendar_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_labels_items_no_update" BEFORE UPDATE ON "r_calendar_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_labels_items_no_delete" BEFORE DELETE ON "r_calendar_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_epoch_no_update" BEFORE UPDATE ON "r_calendar_def_epoch" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_epoch_no_delete" BEFORE DELETE ON "r_calendar_def_epoch" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_unit_structure_no_update" BEFORE UPDATE ON "r_calendar_def_unit_structure" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_unit_structure_no_delete" BEFORE DELETE ON "r_calendar_def_unit_structure" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_unit_structure_items_no_update" BEFORE UPDATE ON "r_calendar_def_unit_structure_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_unit_structure_items_no_delete" BEFORE DELETE ON "r_calendar_def_unit_structure_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_conversions_no_update" BEFORE UPDATE ON "r_calendar_def_conversions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_conversions_no_delete" BEFORE DELETE ON "r_calendar_def_conversions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_conversions_items_no_update" BEFORE UPDATE ON "r_calendar_def_conversions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_calendar_def_conversions_items_no_delete" BEFORE DELETE ON "r_calendar_def_conversions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v36_no_update" BEFORE UPDATE ON "r_domain_operation_v36" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v36_no_delete" BEFORE DELETE ON "r_domain_operation_v36" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_no_update" BEFORE UPDATE ON "r_value_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_no_delete" BEFORE DELETE ON "r_value_def" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_labels_no_update" BEFORE UPDATE ON "r_value_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_labels_no_delete" BEFORE DELETE ON "r_value_def_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_labels_items_no_update" BEFORE UPDATE ON "r_value_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_labels_items_no_delete" BEFORE DELETE ON "r_value_def_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_fields_no_update" BEFORE UPDATE ON "r_value_def_fields" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_fields_no_delete" BEFORE DELETE ON "r_value_def_fields" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_fields_items_no_update" BEFORE UPDATE ON "r_value_def_fields_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_value_def_fields_items_no_delete" BEFORE DELETE ON "r_value_def_fields_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v37_no_update" BEFORE UPDATE ON "r_domain_operation_v37" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v37_no_delete" BEFORE DELETE ON "r_domain_operation_v37" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_no_update" BEFORE UPDATE ON "r_rule" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_no_delete" BEFORE DELETE ON "r_rule" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_knowledge_policy_no_update" BEFORE UPDATE ON "r_rule_knowledge_policy" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_knowledge_policy_no_delete" BEFORE DELETE ON "r_rule_knowledge_policy" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_channel_chronology_no_update" BEFORE UPDATE ON "r_rule_channel_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_channel_chronology_no_delete" BEFORE DELETE ON "r_rule_channel_chronology" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_labels_no_update" BEFORE UPDATE ON "r_rule_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_labels_no_delete" BEFORE DELETE ON "r_rule_labels" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_labels_items_no_update" BEFORE UPDATE ON "r_rule_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_labels_items_no_delete" BEFORE DELETE ON "r_rule_labels_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_subject_types_no_update" BEFORE UPDATE ON "r_rule_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_subject_types_no_delete" BEFORE DELETE ON "r_rule_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_subject_types_items_no_update" BEFORE UPDATE ON "r_rule_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_subject_types_items_no_delete" BEFORE DELETE ON "r_rule_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_target_predicates_no_update" BEFORE UPDATE ON "r_rule_target_predicates" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_target_predicates_no_delete" BEFORE DELETE ON "r_rule_target_predicates" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_target_predicates_items_no_update" BEFORE UPDATE ON "r_rule_target_predicates_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_target_predicates_items_no_delete" BEFORE DELETE ON "r_rule_target_predicates_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_capabilities_no_update" BEFORE UPDATE ON "r_rule_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_capabilities_no_delete" BEFORE DELETE ON "r_rule_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_capabilities_items_no_update" BEFORE UPDATE ON "r_rule_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_rule_capabilities_items_no_delete" BEFORE DELETE ON "r_rule_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v38_no_update" BEFORE UPDATE ON "r_domain_operation_v38" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v38_no_delete" BEFORE DELETE ON "r_domain_operation_v38" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_decl_no_update" BEFORE UPDATE ON "r_completeness_decl" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_decl_no_delete" BEFORE DELETE ON "r_completeness_decl" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_decl_members_no_update" BEFORE UPDATE ON "r_completeness_decl_members" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_decl_members_no_delete" BEFORE DELETE ON "r_completeness_decl_members" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_decl_members_items_no_update" BEFORE UPDATE ON "r_completeness_decl_members_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_completeness_decl_members_items_no_delete" BEFORE DELETE ON "r_completeness_decl_members_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v39_no_update" BEFORE UPDATE ON "r_domain_operation_v39" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v39_no_delete" BEFORE DELETE ON "r_domain_operation_v39" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_creative_boundary_no_update" BEFORE UPDATE ON "r_creative_boundary" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_creative_boundary_no_delete" BEFORE DELETE ON "r_creative_boundary" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_creative_boundary_constraints_no_update" BEFORE UPDATE ON "r_creative_boundary_constraints" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_creative_boundary_constraints_no_delete" BEFORE DELETE ON "r_creative_boundary_constraints" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_creative_boundary_constraints_items_no_update" BEFORE UPDATE ON "r_creative_boundary_constraints_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_creative_boundary_constraints_items_no_delete" BEFORE DELETE ON "r_creative_boundary_constraints_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v40_no_update" BEFORE UPDATE ON "r_domain_operation_v40" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v40_no_delete" BEFORE DELETE ON "r_domain_operation_v40" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_exception_no_update" BEFORE UPDATE ON "r_exception" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_exception_no_delete" BEFORE DELETE ON "r_exception" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_exception_rule_version_no_update" BEFORE UPDATE ON "r_exception_rule_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_exception_rule_version_no_delete" BEFORE DELETE ON "r_exception_rule_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v41_no_update" BEFORE UPDATE ON "r_domain_operation_v41" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v41_no_delete" BEFORE DELETE ON "r_domain_operation_v41" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_no_update" BEFORE UPDATE ON "r_anchor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_no_delete" BEFORE DELETE ON "r_anchor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_context_no_update" BEFORE UPDATE ON "r_anchor_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_anchor_context_no_delete" BEFORE DELETE ON "r_anchor_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v42_no_update" BEFORE UPDATE ON "r_domain_operation_v42" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v42_no_delete" BEFORE DELETE ON "r_domain_operation_v42" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v43_no_update" BEFORE UPDATE ON "r_domain_operation_v43" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v43_no_delete" BEFORE DELETE ON "r_domain_operation_v43" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_issue_decision_no_update" BEFORE UPDATE ON "r_issue_decision" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_issue_decision_no_delete" BEFORE DELETE ON "r_issue_decision" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_issue_decision_fingerprints_no_update" BEFORE UPDATE ON "r_issue_decision_fingerprints" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_issue_decision_fingerprints_no_delete" BEFORE DELETE ON "r_issue_decision_fingerprints" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_issue_decision_fingerprints_items_no_update" BEFORE UPDATE ON "r_issue_decision_fingerprints_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_issue_decision_fingerprints_items_no_delete" BEFORE DELETE ON "r_issue_decision_fingerprints_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v44_no_update" BEFORE UPDATE ON "r_domain_operation_v44" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v44_no_delete" BEFORE DELETE ON "r_domain_operation_v44" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_record_version_no_update" BEFORE UPDATE ON "r_record_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_record_version_no_delete" BEFORE DELETE ON "r_record_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_record_identity_no_update" BEFORE UPDATE ON "r_record_identity" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_record_identity_no_delete" BEFORE DELETE ON "r_record_identity" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v44_expected_version_no_update" BEFORE UPDATE ON "r_domain_operation_v44_expected_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v44_expected_version_no_delete" BEFORE DELETE ON "r_domain_operation_v44_expected_version" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v45_no_update" BEFORE UPDATE ON "r_domain_operation_v45" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v45_no_delete" BEFORE DELETE ON "r_domain_operation_v45" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v46_no_update" BEFORE UPDATE ON "r_domain_operation_v46" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v46_no_delete" BEFORE DELETE ON "r_domain_operation_v46" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v47_no_update" BEFORE UPDATE ON "r_domain_operation_v47" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v47_no_delete" BEFORE DELETE ON "r_domain_operation_v47" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_no_update" BEFORE UPDATE ON "r_domain_pack" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_no_delete" BEFORE DELETE ON "r_domain_pack" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_dependencies_no_update" BEFORE UPDATE ON "r_domain_pack_dependencies" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_dependencies_no_delete" BEFORE DELETE ON "r_domain_pack_dependencies" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_dependencies_items_no_update" BEFORE UPDATE ON "r_domain_pack_dependencies_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_dependencies_items_no_delete" BEFORE DELETE ON "r_domain_pack_dependencies_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_capabilities_no_update" BEFORE UPDATE ON "r_domain_pack_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_capabilities_no_delete" BEFORE DELETE ON "r_domain_pack_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_capabilities_items_no_update" BEFORE UPDATE ON "r_domain_pack_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_capabilities_items_no_delete" BEFORE DELETE ON "r_domain_pack_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_records_no_update" BEFORE UPDATE ON "r_domain_pack_records" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_records_no_delete" BEFORE DELETE ON "r_domain_pack_records" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_records_items_no_update" BEFORE UPDATE ON "r_domain_pack_records_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_pack_records_items_no_delete" BEFORE DELETE ON "r_domain_pack_records_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v48_no_update" BEFORE UPDATE ON "r_domain_operation_v48" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v48_no_delete" BEFORE DELETE ON "r_domain_operation_v48" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v49_no_update" BEFORE UPDATE ON "r_domain_operation_v49" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v49_no_delete" BEFORE DELETE ON "r_domain_operation_v49" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v50_no_update" BEFORE UPDATE ON "r_domain_operation_v50" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v50_no_delete" BEFORE DELETE ON "r_domain_operation_v50" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v50_parent_no_update" BEFORE UPDATE ON "r_domain_operation_v50_parent" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v50_parent_no_delete" BEFORE DELETE ON "r_domain_operation_v50_parent" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v51_no_update" BEFORE UPDATE ON "r_domain_operation_v51" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v51_no_delete" BEFORE DELETE ON "r_domain_operation_v51" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v51_classification_no_update" BEFORE UPDATE ON "r_domain_operation_v51_classification" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v51_classification_no_delete" BEFORE DELETE ON "r_domain_operation_v51_classification" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v51_world_associations_no_update" BEFORE UPDATE ON "r_domain_operation_v51_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v51_world_associations_no_delete" BEFORE DELETE ON "r_domain_operation_v51_world_associations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v51_world_associations_items_no_update" BEFORE UPDATE ON "r_domain_operation_v51_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v51_world_associations_items_no_delete" BEFORE DELETE ON "r_domain_operation_v51_world_associations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v52_no_update" BEFORE UPDATE ON "r_domain_operation_v52" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v52_no_delete" BEFORE DELETE ON "r_domain_operation_v52" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v52_subject_types_no_update" BEFORE UPDATE ON "r_domain_operation_v52_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v52_subject_types_no_delete" BEFORE DELETE ON "r_domain_operation_v52_subject_types" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v52_subject_types_items_no_update" BEFORE UPDATE ON "r_domain_operation_v52_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v52_subject_types_items_no_delete" BEFORE DELETE ON "r_domain_operation_v52_subject_types_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_attribute_evidence_no_update" BEFORE UPDATE ON "r_attribute_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_attribute_evidence_no_delete" BEFORE DELETE ON "r_attribute_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_attribute_evidence_alternatives_no_update" BEFORE UPDATE ON "r_attribute_evidence_alternatives" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_attribute_evidence_alternatives_no_delete" BEFORE DELETE ON "r_attribute_evidence_alternatives" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_attribute_evidence_alternatives_items_no_update" BEFORE UPDATE ON "r_attribute_evidence_alternatives_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_attribute_evidence_alternatives_items_no_delete" BEFORE DELETE ON "r_attribute_evidence_alternatives_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v53_no_update" BEFORE UPDATE ON "r_domain_operation_v53" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v53_no_delete" BEFORE DELETE ON "r_domain_operation_v53" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v54_no_update" BEFORE UPDATE ON "r_domain_operation_v54" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v54_no_delete" BEFORE DELETE ON "r_domain_operation_v54" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v55_no_update" BEFORE UPDATE ON "r_domain_operation_v55" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_domain_operation_v55_no_delete" BEFORE DELETE ON "r_domain_operation_v55" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_context_no_update" BEFORE UPDATE ON "r_stored_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_context_no_delete" BEFORE DELETE ON "r_stored_context" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_no_update" BEFORE UPDATE ON "r_frame" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_no_delete" BEFORE DELETE ON "r_frame" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_time_no_update" BEFORE UPDATE ON "r_frame_time" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_time_no_delete" BEFORE DELETE ON "r_frame_time" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_time_v0_no_update" BEFORE UPDATE ON "r_frame_time_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_time_v0_no_delete" BEFORE DELETE ON "r_frame_time_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_time_v1_no_update" BEFORE UPDATE ON "r_frame_time_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_time_v1_no_delete" BEFORE DELETE ON "r_frame_time_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_time_v2_no_update" BEFORE UPDATE ON "r_frame_time_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_time_v2_no_delete" BEFORE DELETE ON "r_frame_time_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_time_side_no_update" BEFORE UPDATE ON "r_event_time_side" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_event_time_side_no_delete" BEFORE DELETE ON "r_event_time_side" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_perspective_no_update" BEFORE UPDATE ON "r_perspective" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_perspective_no_delete" BEFORE DELETE ON "r_perspective" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_perspective_v1_no_update" BEFORE UPDATE ON "r_perspective_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_perspective_v1_no_delete" BEFORE DELETE ON "r_perspective_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_perspective_v2_no_update" BEFORE UPDATE ON "r_perspective_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_perspective_v2_no_delete" BEFORE DELETE ON "r_perspective_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_reader_scene_no_update" BEFORE UPDATE ON "r_frame_reader_scene" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_reader_scene_no_delete" BEFORE DELETE ON "r_frame_reader_scene" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_personal_sequence_no_update" BEFORE UPDATE ON "r_frame_personal_sequence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_frame_personal_sequence_no_delete" BEFORE DELETE ON "r_frame_personal_sequence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_proposal_no_update" BEFORE UPDATE ON "r_stored_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_proposal_no_delete" BEFORE DELETE ON "r_stored_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_no_update" BEFORE UPDATE ON "r_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_no_delete" BEFORE DELETE ON "r_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_world_scope_no_update" BEFORE UPDATE ON "r_proposal_world_scope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_world_scope_no_delete" BEFORE DELETE ON "r_proposal_world_scope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_operations_no_update" BEFORE UPDATE ON "r_proposal_operations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_operations_no_delete" BEFORE DELETE ON "r_proposal_operations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_operations_items_no_update" BEFORE UPDATE ON "r_proposal_operations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_operations_items_no_delete" BEFORE DELETE ON "r_proposal_operations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_compiled_changes_no_update" BEFORE UPDATE ON "r_proposal_compiled_changes" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_compiled_changes_no_delete" BEFORE DELETE ON "r_proposal_compiled_changes" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_compiled_changes_items_no_update" BEFORE UPDATE ON "r_proposal_compiled_changes_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_compiled_changes_items_no_delete" BEFORE DELETE ON "r_proposal_compiled_changes_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_compiled_change_no_update" BEFORE UPDATE ON "r_compiled_change" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_compiled_change_no_delete" BEFORE DELETE ON "r_compiled_change" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_compiled_change_expected_no_update" BEFORE UPDATE ON "r_compiled_change_expected" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_compiled_change_expected_no_delete" BEFORE DELETE ON "r_compiled_change_expected" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_compiled_change_next_no_update" BEFORE UPDATE ON "r_compiled_change_next" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_compiled_change_next_no_delete" BEFORE DELETE ON "r_compiled_change_next" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_proposal_changes_no_update" BEFORE UPDATE ON "r_stored_proposal_changes" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_proposal_changes_no_delete" BEFORE DELETE ON "r_stored_proposal_changes" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_proposal_changes_items_no_update" BEFORE UPDATE ON "r_stored_proposal_changes_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_proposal_changes_items_no_delete" BEFORE DELETE ON "r_stored_proposal_changes_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assignment_no_update" BEFORE UPDATE ON "r_assignment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assignment_no_delete" BEFORE DELETE ON "r_assignment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assignment_expected_no_update" BEFORE UPDATE ON "r_assignment_expected" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assignment_expected_no_delete" BEFORE DELETE ON "r_assignment_expected" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assignment_next_no_update" BEFORE UPDATE ON "r_assignment_next" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assignment_next_no_delete" BEFORE DELETE ON "r_assignment_next" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_footprint_no_update" BEFORE UPDATE ON "r_footprint" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_footprint_no_delete" BEFORE DELETE ON "r_footprint" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_footprint_worlds_no_update" BEFORE UPDATE ON "r_footprint_worlds" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_footprint_worlds_no_delete" BEFORE DELETE ON "r_footprint_worlds" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_footprint_worlds_items_no_update" BEFORE UPDATE ON "r_footprint_worlds_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_footprint_worlds_items_no_delete" BEFORE DELETE ON "r_footprint_worlds_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_checked_no_update" BEFORE UPDATE ON "r_checked" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_checked_no_delete" BEFORE DELETE ON "r_checked" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_no_update" BEFORE UPDATE ON "r_validation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_no_delete" BEFORE DELETE ON "r_validation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_operation_id_no_update" BEFORE UPDATE ON "r_validation_operation_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_operation_id_no_delete" BEFORE DELETE ON "r_validation_operation_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_findings_no_update" BEFORE UPDATE ON "r_validation_findings" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_findings_no_delete" BEFORE DELETE ON "r_validation_findings" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_findings_items_no_update" BEFORE UPDATE ON "r_validation_findings_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_findings_items_no_delete" BEFORE DELETE ON "r_validation_findings_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_finding_no_update" BEFORE UPDATE ON "r_finding" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_finding_no_delete" BEFORE DELETE ON "r_finding" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_finding_evidence_no_update" BEFORE UPDATE ON "r_finding_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_finding_evidence_no_delete" BEFORE DELETE ON "r_finding_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_finding_evidence_items_no_update" BEFORE UPDATE ON "r_finding_evidence_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_finding_evidence_items_no_delete" BEFORE DELETE ON "r_finding_evidence_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_opposing_evidence_no_update" BEFORE UPDATE ON "r_validation_opposing_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_opposing_evidence_no_delete" BEFORE DELETE ON "r_validation_opposing_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_opposing_evidence_items_no_update" BEFORE UPDATE ON "r_validation_opposing_evidence_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_opposing_evidence_items_no_delete" BEFORE DELETE ON "r_validation_opposing_evidence_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_no_update" BEFORE UPDATE ON "r_opposing_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_no_delete" BEFORE DELETE ON "r_opposing_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_chain_no_update" BEFORE UPDATE ON "r_opposing_chain" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_chain_no_delete" BEFORE DELETE ON "r_opposing_chain" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_chain_dependencies_no_update" BEFORE UPDATE ON "r_opposing_chain_dependencies" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_chain_dependencies_no_delete" BEFORE DELETE ON "r_opposing_chain_dependencies" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_chain_dependencies_items_no_update" BEFORE UPDATE ON "r_opposing_chain_dependencies_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_chain_dependencies_items_no_delete" BEFORE DELETE ON "r_opposing_chain_dependencies_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_applicability_no_update" BEFORE UPDATE ON "r_opposing_evidence_applicability" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_applicability_no_delete" BEFORE DELETE ON "r_opposing_evidence_applicability" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_realm_no_update" BEFORE UPDATE ON "r_opposing_evidence_realm" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_realm_no_delete" BEFORE DELETE ON "r_opposing_evidence_realm" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_no_update" BEFORE UPDATE ON "r_opposing_intersection" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_no_delete" BEFORE DELETE ON "r_opposing_intersection" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v0_no_update" BEFORE UPDATE ON "r_opposing_intersection_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v0_no_delete" BEFORE DELETE ON "r_opposing_intersection_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v1_no_update" BEFORE UPDATE ON "r_opposing_intersection_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v1_no_delete" BEFORE DELETE ON "r_opposing_intersection_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v2_no_update" BEFORE UPDATE ON "r_opposing_intersection_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v2_no_delete" BEFORE DELETE ON "r_opposing_intersection_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v2_guaranteed_no_update" BEFORE UPDATE ON "r_opposing_intersection_v2_guaranteed" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v2_guaranteed_no_delete" BEFORE DELETE ON "r_opposing_intersection_v2_guaranteed" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v3_no_update" BEFORE UPDATE ON "r_opposing_intersection_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_intersection_v3_no_delete" BEFORE DELETE ON "r_opposing_intersection_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_unresolved_reasons_no_update" BEFORE UPDATE ON "r_opposing_evidence_unresolved_reasons" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_unresolved_reasons_no_delete" BEFORE DELETE ON "r_opposing_evidence_unresolved_reasons" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_unresolved_reasons_items_no_update" BEFORE UPDATE ON "r_opposing_evidence_unresolved_reasons_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_unresolved_reasons_items_no_delete" BEFORE DELETE ON "r_opposing_evidence_unresolved_reasons_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_policy_versions_no_update" BEFORE UPDATE ON "r_opposing_evidence_policy_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_policy_versions_no_delete" BEFORE DELETE ON "r_opposing_evidence_policy_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_policy_versions_items_no_update" BEFORE UPDATE ON "r_opposing_evidence_policy_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_policy_versions_items_no_delete" BEFORE DELETE ON "r_opposing_evidence_policy_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_exception_versions_no_update" BEFORE UPDATE ON "r_opposing_evidence_exception_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_exception_versions_no_delete" BEFORE DELETE ON "r_opposing_evidence_exception_versions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_exception_versions_items_no_update" BEFORE UPDATE ON "r_opposing_evidence_exception_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_opposing_evidence_exception_versions_items_no_delete" BEFORE DELETE ON "r_opposing_evidence_exception_versions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_unsupported_capabilities_no_update" BEFORE UPDATE ON "r_validation_unsupported_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_unsupported_capabilities_no_delete" BEFORE DELETE ON "r_validation_unsupported_capabilities" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_unsupported_capabilities_items_no_update" BEFORE UPDATE ON "r_validation_unsupported_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_unsupported_capabilities_items_no_delete" BEFORE DELETE ON "r_validation_unsupported_capabilities_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_checked_report_no_update" BEFORE UPDATE ON "r_checked_report" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_checked_report_no_delete" BEFORE DELETE ON "r_checked_report" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_report_no_update" BEFORE UPDATE ON "r_validation_report" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_report_no_delete" BEFORE DELETE ON "r_validation_report" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_report_v0_no_update" BEFORE UPDATE ON "r_validation_report_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_report_v0_no_delete" BEFORE DELETE ON "r_validation_report_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_no_update" BEFORE UPDATE ON "r_submitted_input" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_no_delete" BEFORE DELETE ON "r_submitted_input" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v0_no_update" BEFORE UPDATE ON "r_submitted_input_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v0_no_delete" BEFORE DELETE ON "r_submitted_input_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v1_no_update" BEFORE UPDATE ON "r_submitted_input_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v1_no_delete" BEFORE DELETE ON "r_submitted_input_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_ref_no_update" BEFORE UPDATE ON "r_proposal_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_proposal_ref_no_delete" BEFORE DELETE ON "r_proposal_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v2_no_update" BEFORE UPDATE ON "r_submitted_input_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v2_no_delete" BEFORE DELETE ON "r_submitted_input_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v2_sources_no_update" BEFORE UPDATE ON "r_submitted_input_v2_sources" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v2_sources_no_delete" BEFORE DELETE ON "r_submitted_input_v2_sources" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v2_sources_items_no_update" BEFORE UPDATE ON "r_submitted_input_v2_sources_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_submitted_input_v2_sources_items_no_delete" BEFORE DELETE ON "r_submitted_input_v2_sources_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_no_update" BEFORE UPDATE ON "r_source_binding" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_no_delete" BEFORE DELETE ON "r_source_binding" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_version_ref_no_update" BEFORE UPDATE ON "r_assessment_version_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_version_ref_no_delete" BEFORE DELETE ON "r_assessment_version_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_ranges_no_update" BEFORE UPDATE ON "r_source_binding_ranges" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_ranges_no_delete" BEFORE DELETE ON "r_source_binding_ranges" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_ranges_items_no_update" BEFORE UPDATE ON "r_source_binding_ranges_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_ranges_items_no_delete" BEFORE DELETE ON "r_source_binding_ranges_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_byte_range_no_update" BEFORE UPDATE ON "r_byte_range" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_byte_range_no_delete" BEFORE DELETE ON "r_byte_range" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_work_edition_no_update" BEFORE UPDATE ON "r_source_binding_work_edition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_work_edition_no_delete" BEFORE DELETE ON "r_source_binding_work_edition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_passage_id_no_update" BEFORE UPDATE ON "r_source_binding_passage_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_binding_passage_id_no_delete" BEFORE DELETE ON "r_source_binding_passage_id" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_no_update" BEFORE UPDATE ON "r_assessment_state" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_no_delete" BEFORE DELETE ON "r_assessment_state" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v0_no_update" BEFORE UPDATE ON "r_assessment_state_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v0_no_delete" BEFORE DELETE ON "r_assessment_state_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v1_no_update" BEFORE UPDATE ON "r_assessment_state_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v1_no_delete" BEFORE DELETE ON "r_assessment_state_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v2_no_update" BEFORE UPDATE ON "r_assessment_state_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v2_no_delete" BEFORE DELETE ON "r_assessment_state_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v3_no_update" BEFORE UPDATE ON "r_assessment_state_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v3_no_delete" BEFORE DELETE ON "r_assessment_state_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_ref_no_update" BEFORE UPDATE ON "r_assessment_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_ref_no_delete" BEFORE DELETE ON "r_assessment_ref" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v3_reasons_no_update" BEFORE UPDATE ON "r_assessment_state_v3_reasons" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v3_reasons_no_delete" BEFORE DELETE ON "r_assessment_state_v3_reasons" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v3_reasons_items_no_update" BEFORE UPDATE ON "r_assessment_state_v3_reasons_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v3_reasons_items_no_delete" BEFORE DELETE ON "r_assessment_state_v3_reasons_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v4_no_update" BEFORE UPDATE ON "r_assessment_state_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_state_v4_no_delete" BEFORE DELETE ON "r_assessment_state_v4" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_report_v0_final_binding_digest_no_update" BEFORE UPDATE ON "r_validation_report_v0_final_binding_digest" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_report_v0_final_binding_digest_no_delete" BEFORE DELETE ON "r_validation_report_v0_final_binding_digest" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_report_v1_no_update" BEFORE UPDATE ON "r_validation_report_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_report_v1_no_delete" BEFORE DELETE ON "r_validation_report_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_restricted_input_no_update" BEFORE UPDATE ON "r_restricted_input" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_restricted_input_no_delete" BEFORE DELETE ON "r_restricted_input" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_restricted_input_v0_no_update" BEFORE UPDATE ON "r_restricted_input_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_restricted_input_v0_no_delete" BEFORE DELETE ON "r_restricted_input_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_restricted_assessment_no_update" BEFORE UPDATE ON "r_restricted_assessment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_restricted_assessment_no_delete" BEFORE DELETE ON "r_restricted_assessment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_restricted_assessment_v0_no_update" BEFORE UPDATE ON "r_restricted_assessment_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_restricted_assessment_v0_no_delete" BEFORE DELETE ON "r_restricted_assessment_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_checked_capture_no_update" BEFORE UPDATE ON "r_checked_capture" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_checked_capture_no_delete" BEFORE DELETE ON "r_checked_capture" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_capture_no_update" BEFORE UPDATE ON "r_validation_capture" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_capture_no_delete" BEFORE DELETE ON "r_validation_capture" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_selection_no_update" BEFORE UPDATE ON "r_assessment_selection" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_selection_no_delete" BEFORE DELETE ON "r_assessment_selection" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_selection_proposal_no_update" BEFORE UPDATE ON "r_assessment_selection_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_selection_proposal_no_delete" BEFORE DELETE ON "r_assessment_selection_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_selection_selected_no_update" BEFORE UPDATE ON "r_assessment_selection_selected" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_selection_selected_no_delete" BEFORE DELETE ON "r_assessment_selection_selected" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_capture_latest_proposal_key_no_update" BEFORE UPDATE ON "r_validation_capture_latest_proposal_key" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_capture_latest_proposal_key_no_delete" BEFORE DELETE ON "r_validation_capture_latest_proposal_key" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_capture_authority_sequence_no_update" BEFORE UPDATE ON "r_validation_capture_authority_sequence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_validation_capture_authority_sequence_no_delete" BEFORE DELETE ON "r_validation_capture_authority_sequence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_operation_no_update" BEFORE UPDATE ON "r_stored_operation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_operation_no_delete" BEFORE DELETE ON "r_stored_operation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_no_update" BEFORE UPDATE ON "r_operation_status_internal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_no_delete" BEFORE DELETE ON "r_operation_status_internal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_validation_no_update" BEFORE UPDATE ON "r_operation_status_internal_validation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_validation_no_delete" BEFORE DELETE ON "r_operation_status_internal_validation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_failure_no_update" BEFORE UPDATE ON "r_operation_status_internal_failure" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_failure_no_delete" BEFORE DELETE ON "r_operation_status_internal_failure" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_proposal_no_update" BEFORE UPDATE ON "r_operation_status_internal_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_proposal_no_delete" BEFORE DELETE ON "r_operation_status_internal_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_receipt_no_update" BEFORE UPDATE ON "r_operation_status_internal_receipt" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_operation_status_internal_receipt_no_delete" BEFORE DELETE ON "r_operation_status_internal_receipt" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_receipt_no_update" BEFORE UPDATE ON "r_commit_receipt" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_receipt_no_delete" BEFORE DELETE ON "r_commit_receipt" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_operation_input_no_update" BEFORE UPDATE ON "r_stored_operation_input" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_operation_input_no_delete" BEFORE DELETE ON "r_stored_operation_input" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_input_no_update" BEFORE UPDATE ON "r_commit_input" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_input_no_delete" BEFORE DELETE ON "r_commit_input" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_input_changes_no_update" BEFORE UPDATE ON "r_commit_input_changes" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_input_changes_no_delete" BEFORE DELETE ON "r_commit_input_changes" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_input_changes_items_no_update" BEFORE UPDATE ON "r_commit_input_changes_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_commit_input_changes_items_no_delete" BEFORE DELETE ON "r_commit_input_changes_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_operation_validation_capture_no_update" BEFORE UPDATE ON "r_stored_operation_validation_capture" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_stored_operation_validation_capture_no_delete" BEFORE DELETE ON "r_stored_operation_validation_capture" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_approval_evidence_no_update" BEFORE UPDATE ON "r_approval_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_approval_evidence_no_delete" BEFORE DELETE ON "r_approval_evidence" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_envelope_no_update" BEFORE UPDATE ON "r_assessment_envelope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_envelope_no_delete" BEFORE DELETE ON "r_assessment_envelope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_no_update" BEFORE UPDATE ON "r_source_assessment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_no_delete" BEFORE DELETE ON "r_source_assessment" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_proposal_no_update" BEFORE UPDATE ON "r_source_assessment_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_proposal_no_delete" BEFORE DELETE ON "r_source_assessment_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessor_no_update" BEFORE UPDATE ON "r_assessor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessor_no_delete" BEFORE DELETE ON "r_assessor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessor_tool_no_update" BEFORE UPDATE ON "r_assessor_tool" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessor_tool_no_delete" BEFORE DELETE ON "r_assessor_tool" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_tool_identity_no_update" BEFORE UPDATE ON "r_tool_identity" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_tool_identity_no_delete" BEFORE DELETE ON "r_tool_identity" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_sources_no_update" BEFORE UPDATE ON "r_source_assessment_sources" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_sources_no_delete" BEFORE DELETE ON "r_source_assessment_sources" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_sources_items_no_update" BEFORE UPDATE ON "r_source_assessment_sources_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_sources_items_no_delete" BEFORE DELETE ON "r_source_assessment_sources_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_dependencies_no_update" BEFORE UPDATE ON "r_source_assessment_dependencies" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_dependencies_no_delete" BEFORE DELETE ON "r_source_assessment_dependencies" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_dependencies_items_no_update" BEFORE UPDATE ON "r_source_assessment_dependencies_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_dependencies_items_no_delete" BEFORE DELETE ON "r_source_assessment_dependencies_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_declared_inventory_no_update" BEFORE UPDATE ON "r_source_assessment_declared_inventory" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_declared_inventory_no_delete" BEFORE DELETE ON "r_source_assessment_declared_inventory" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_declared_inventory_items_no_update" BEFORE UPDATE ON "r_source_assessment_declared_inventory_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_declared_inventory_items_no_delete" BEFORE DELETE ON "r_source_assessment_declared_inventory_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_no_update" BEFORE UPDATE ON "r_material_item" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_no_delete" BEFORE DELETE ON "r_material_item" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_mapping_ids_no_update" BEFORE UPDATE ON "r_material_item_mapping_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_mapping_ids_no_delete" BEFORE DELETE ON "r_material_item_mapping_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_mapping_ids_items_no_update" BEFORE UPDATE ON "r_material_item_mapping_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_mapping_ids_items_no_delete" BEFORE DELETE ON "r_material_item_mapping_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_unresolved_ids_no_update" BEFORE UPDATE ON "r_material_item_unresolved_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_unresolved_ids_no_delete" BEFORE DELETE ON "r_material_item_unresolved_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_unresolved_ids_items_no_update" BEFORE UPDATE ON "r_material_item_unresolved_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_material_item_unresolved_ids_items_no_delete" BEFORE DELETE ON "r_material_item_unresolved_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_inventory_declaration_no_update" BEFORE UPDATE ON "r_inventory_declaration" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_inventory_declaration_no_delete" BEFORE DELETE ON "r_inventory_declaration" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_inventory_declaration_exclusions_no_update" BEFORE UPDATE ON "r_inventory_declaration_exclusions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_inventory_declaration_exclusions_no_delete" BEFORE DELETE ON "r_inventory_declaration_exclusions" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_inventory_declaration_exclusions_items_no_update" BEFORE UPDATE ON "r_inventory_declaration_exclusions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_inventory_declaration_exclusions_items_no_delete" BEFORE DELETE ON "r_inventory_declaration_exclusions_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_exclusion_no_update" BEFORE UPDATE ON "r_exclusion" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_exclusion_no_delete" BEFORE DELETE ON "r_exclusion" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_claim_mappings_no_update" BEFORE UPDATE ON "r_source_assessment_claim_mappings" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_claim_mappings_no_delete" BEFORE DELETE ON "r_source_assessment_claim_mappings" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_claim_mappings_items_no_update" BEFORE UPDATE ON "r_source_assessment_claim_mappings_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_claim_mappings_items_no_delete" BEFORE DELETE ON "r_source_assessment_claim_mappings_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_no_update" BEFORE UPDATE ON "r_claim_mapping" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_no_delete" BEFORE DELETE ON "r_claim_mapping" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_item_ids_no_update" BEFORE UPDATE ON "r_claim_mapping_item_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_item_ids_no_delete" BEFORE DELETE ON "r_claim_mapping_item_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_item_ids_items_no_update" BEFORE UPDATE ON "r_claim_mapping_item_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_item_ids_items_no_delete" BEFORE DELETE ON "r_claim_mapping_item_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_referents_no_update" BEFORE UPDATE ON "r_claim_mapping_referents" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_referents_no_delete" BEFORE DELETE ON "r_claim_mapping_referents" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_referents_items_no_update" BEFORE UPDATE ON "r_claim_mapping_referents_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_referents_items_no_delete" BEFORE DELETE ON "r_claim_mapping_referents_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_world_no_update" BEFORE UPDATE ON "r_claim_mapping_world" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_world_no_delete" BEFORE DELETE ON "r_claim_mapping_world" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_realm_no_update" BEFORE UPDATE ON "r_claim_mapping_realm" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_realm_no_delete" BEFORE DELETE ON "r_claim_mapping_realm" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_position_no_update" BEFORE UPDATE ON "r_position" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_position_no_delete" BEFORE DELETE ON "r_position" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_position_v0_no_update" BEFORE UPDATE ON "r_position_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_position_v0_no_delete" BEFORE DELETE ON "r_position_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_position_v1_no_update" BEFORE UPDATE ON "r_position_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_position_v1_no_delete" BEFORE DELETE ON "r_position_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_position_v2_no_update" BEFORE UPDATE ON "r_position_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_position_v2_no_delete" BEFORE DELETE ON "r_position_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_no_update" BEFORE UPDATE ON "r_semantic_mapping" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_no_delete" BEFORE DELETE ON "r_semantic_mapping" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v0_no_update" BEFORE UPDATE ON "r_semantic_mapping_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v0_no_delete" BEFORE DELETE ON "r_semantic_mapping_v0" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v0_roles_no_update" BEFORE UPDATE ON "r_semantic_mapping_v0_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v0_roles_no_delete" BEFORE DELETE ON "r_semantic_mapping_v0_roles" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v0_roles_items_no_update" BEFORE UPDATE ON "r_semantic_mapping_v0_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v0_roles_items_no_delete" BEFORE DELETE ON "r_semantic_mapping_v0_roles_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_role_participant_no_update" BEFORE UPDATE ON "r_role_participant" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_role_participant_no_delete" BEFORE DELETE ON "r_role_participant" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_no_update" BEFORE UPDATE ON "r_semantic_mapping_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_no_delete" BEFORE DELETE ON "r_semantic_mapping_v1" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_participants_no_update" BEFORE UPDATE ON "r_semantic_mapping_v1_participants" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_participants_no_delete" BEFORE DELETE ON "r_semantic_mapping_v1_participants" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_participants_items_no_update" BEFORE UPDATE ON "r_semantic_mapping_v1_participants_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_participants_items_no_delete" BEFORE DELETE ON "r_semantic_mapping_v1_participants_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_prerequisites_no_update" BEFORE UPDATE ON "r_semantic_mapping_v1_prerequisites" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_prerequisites_no_delete" BEFORE DELETE ON "r_semantic_mapping_v1_prerequisites" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_prerequisites_items_no_update" BEFORE UPDATE ON "r_semantic_mapping_v1_prerequisites_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_prerequisites_items_no_delete" BEFORE DELETE ON "r_semantic_mapping_v1_prerequisites_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_effects_no_update" BEFORE UPDATE ON "r_semantic_mapping_v1_effects" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_effects_no_delete" BEFORE DELETE ON "r_semantic_mapping_v1_effects" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_effects_items_no_update" BEFORE UPDATE ON "r_semantic_mapping_v1_effects_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v1_effects_items_no_delete" BEFORE DELETE ON "r_semantic_mapping_v1_effects_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v2_no_update" BEFORE UPDATE ON "r_semantic_mapping_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v2_no_delete" BEFORE DELETE ON "r_semantic_mapping_v2" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v2_acquisition_no_update" BEFORE UPDATE ON "r_semantic_mapping_v2_acquisition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v2_acquisition_no_delete" BEFORE DELETE ON "r_semantic_mapping_v2_acquisition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v2_acquisition_items_no_update" BEFORE UPDATE ON "r_semantic_mapping_v2_acquisition_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v2_acquisition_items_no_delete" BEFORE DELETE ON "r_semantic_mapping_v2_acquisition_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v3_no_update" BEFORE UPDATE ON "r_semantic_mapping_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v3_no_delete" BEFORE DELETE ON "r_semantic_mapping_v3" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v3_implied_claims_no_update" BEFORE UPDATE ON "r_semantic_mapping_v3_implied_claims" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v3_implied_claims_no_delete" BEFORE DELETE ON "r_semantic_mapping_v3_implied_claims" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v3_implied_claims_items_no_update" BEFORE UPDATE ON "r_semantic_mapping_v3_implied_claims_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_semantic_mapping_v3_implied_claims_items_no_delete" BEFORE DELETE ON "r_semantic_mapping_v3_implied_claims_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_candidate_links_no_update" BEFORE UPDATE ON "r_claim_mapping_candidate_links" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_candidate_links_no_delete" BEFORE DELETE ON "r_claim_mapping_candidate_links" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_candidate_links_items_no_update" BEFORE UPDATE ON "r_claim_mapping_candidate_links_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_claim_mapping_candidate_links_items_no_delete" BEFORE DELETE ON "r_claim_mapping_candidate_links_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_candidate_link_no_update" BEFORE UPDATE ON "r_candidate_link" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_candidate_link_no_delete" BEFORE DELETE ON "r_candidate_link" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_unresolved_no_update" BEFORE UPDATE ON "r_source_assessment_unresolved" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_unresolved_no_delete" BEFORE DELETE ON "r_source_assessment_unresolved" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_unresolved_items_no_update" BEFORE UPDATE ON "r_source_assessment_unresolved_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_assessment_unresolved_items_no_delete" BEFORE DELETE ON "r_source_assessment_unresolved_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unresolved_disposition_no_update" BEFORE UPDATE ON "r_unresolved_disposition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unresolved_disposition_no_delete" BEFORE DELETE ON "r_unresolved_disposition" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unresolved_disposition_item_ids_no_update" BEFORE UPDATE ON "r_unresolved_disposition_item_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unresolved_disposition_item_ids_no_delete" BEFORE DELETE ON "r_unresolved_disposition_item_ids" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unresolved_disposition_item_ids_items_no_update" BEFORE UPDATE ON "r_unresolved_disposition_item_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_unresolved_disposition_item_ids_items_no_delete" BEFORE DELETE ON "r_unresolved_disposition_item_ids_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_receipt_no_update" BEFORE UPDATE ON "r_assessment_receipt" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_receipt_no_delete" BEFORE DELETE ON "r_assessment_receipt" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_receipt_envelope_no_update" BEFORE UPDATE ON "r_assessment_receipt_envelope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_assessment_receipt_envelope_no_delete" BEFORE DELETE ON "r_assessment_receipt_envelope" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_cursor_no_update" BEFORE UPDATE ON "r_cursor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_cursor_no_delete" BEFORE DELETE ON "r_cursor" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_cancellation_no_update" BEFORE UPDATE ON "r_cancellation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_cancellation_no_delete" BEFORE DELETE ON "r_cancellation" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_reserved_record_no_update" BEFORE UPDATE ON "r_reserved_record" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_reserved_record_no_delete" BEFORE DELETE ON "r_reserved_record" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saved_draft_no_update" BEFORE UPDATE ON "r_saved_draft" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_saved_draft_no_delete" BEFORE DELETE ON "r_saved_draft" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_draft_content_no_update" BEFORE UPDATE ON "r_draft_content" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_draft_content_no_delete" BEFORE DELETE ON "r_draft_content" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_draft_content_operations_no_update" BEFORE UPDATE ON "r_draft_content_operations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_draft_content_operations_no_delete" BEFORE DELETE ON "r_draft_content_operations" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_draft_content_operations_items_no_update" BEFORE UPDATE ON "r_draft_content_operations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_draft_content_operations_items_no_delete" BEFORE DELETE ON "r_draft_content_operations_items" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_draft_content_proposal_no_update" BEFORE UPDATE ON "r_draft_content_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_draft_content_proposal_no_delete" BEFORE DELETE ON "r_draft_content_proposal" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_import_origin_no_update" BEFORE UPDATE ON "r_import_origin" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_import_origin_no_delete" BEFORE DELETE ON "r_import_origin" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_import_admission_no_update" BEFORE UPDATE ON "r_import_admission" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_import_admission_no_delete" BEFORE DELETE ON "r_import_admission" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_import_preview_no_update" BEFORE UPDATE ON "r_import_preview" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_import_preview_no_delete" BEFORE DELETE ON "r_import_preview" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_archive_manifest_no_update" BEFORE UPDATE ON "r_archive_manifest" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_archive_manifest_no_delete" BEFORE DELETE ON "r_archive_manifest" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_validation_binding_no_update" BEFORE UPDATE ON "r_source_validation_binding" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;

CREATE TRIGGER "r_source_validation_binding_no_delete" BEFORE DELETE ON "r_source_validation_binding" BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;
