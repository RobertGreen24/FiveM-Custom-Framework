-- ============================================================================
--  NEXUS FRAMEWORK  ::  Database Schema
--  Engine : MySQL 5.7+ / MariaDB 10.3+
--  Install: mysql -u root -p < sql/nexus.sql
--           or paste into HeidiSQL / phpMyAdmin and run.
-- ============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
--  ACCOUNTS  ::  one row per Rockstar licence (a "player" owns N characters)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_players` (
  `id`            INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `license`       VARCHAR(64)     NOT NULL,
  `license2`      VARCHAR(64)     DEFAULT NULL,
  `discord`       VARCHAR(32)     DEFAULT NULL,
  `steam`         VARCHAR(64)     DEFAULT NULL,
  `fivem`         VARCHAR(64)     DEFAULT NULL,
  `live`          VARCHAR(64)     DEFAULT NULL,
  `xbl`           VARCHAR(64)     DEFAULT NULL,
  `ip`            VARCHAR(46)     DEFAULT NULL,
  `playername`    VARCHAR(80)     DEFAULT NULL COMMENT 'last known FiveM username',
  `admin_level`   TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=none 1=helper 2=mod 3=admin 4=superadmin',
  `priority`      INT             NOT NULL DEFAULT 0 COMMENT 'queue/connection priority',
  `total_playtime` INT UNSIGNED   NOT NULL DEFAULT 0 COMMENT 'seconds across all characters',
  `notes`         TEXT            DEFAULT NULL COMMENT 'staff notes',
  `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen`     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_license` (`license`),
  KEY `idx_discord` (`discord`),
  KEY `idx_ip` (`ip`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  CHARACTERS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_characters` (
  `id`            INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `player_id`     INT UNSIGNED    NOT NULL,
  `slot`          TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `state_id`      SMALLINT UNSIGNED NOT NULL COMMENT 'displayed ID (player.hudId)',
  `first_name`    VARCHAR(32)     NOT NULL,
  `last_name`     VARCHAR(32)     NOT NULL,
  `birth_date`    DATE            DEFAULT NULL,
  `gender`        TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=male 1=female',
  `nationality`   VARCHAR(32)     DEFAULT 'American',
  `phone`         VARCHAR(16)     DEFAULT NULL,

  -- economy
  `cash`          INT             NOT NULL DEFAULT 500,
  `bank`          INT             NOT NULL DEFAULT 5000,
  `black_money`   INT             NOT NULL DEFAULT 0,

  -- employment
  `job`           VARCHAR(32)     NOT NULL DEFAULT 'unemployed',
  `job_grade`     TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `on_duty`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `gang`          VARCHAR(32)     NOT NULL DEFAULT 'none',
  `gang_grade`    TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `callsign`      VARCHAR(16)     DEFAULT NULL,

  -- world position
  `x`             FLOAT           NOT NULL DEFAULT 0,
  `y`             FLOAT           NOT NULL DEFAULT 0,
  `z`             FLOAT           NOT NULL DEFAULT 0,
  `heading`       FLOAT           NOT NULL DEFAULT 0,
  `last_location` VARCHAR(64)     DEFAULT 'legion' COMMENT 'spawn point key',

  -- vitals / metadata
  `health`        TINYINT UNSIGNED NOT NULL DEFAULT 200,
  `armour`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `hunger`        TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `thirst`        TINYINT UNSIGNED NOT NULL DEFAULT 100,
  `stress`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `is_dead`       TINYINT UNSIGNED NOT NULL DEFAULT 0,

  -- blobs
  `skin`          LONGTEXT        DEFAULT NULL COMMENT 'JSON ped appearance',
  `metadata`      LONGTEXT        DEFAULT NULL COMMENT 'JSON free-form flags',
  `licences`      LONGTEXT        DEFAULT NULL COMMENT 'JSON licence table cache',

  `playtime`      INT UNSIGNED    NOT NULL DEFAULT 0 COMMENT 'seconds',
  `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_played`   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_state_id` (`state_id`),
  UNIQUE KEY `uniq_phone` (`phone`),
  UNIQUE KEY `uniq_slot` (`player_id`, `slot`),
  KEY `idx_player` (`player_id`),
  KEY `idx_job` (`job`),
  CONSTRAINT `fk_char_player` FOREIGN KEY (`player_id`)
    REFERENCES `nx_players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  INVENTORY  ::  every container in the world lives here.
--  `owner` =  char:<charId> | trunk:<PLATE> | glove:<PLATE> | stash:<stashId>
--             | drop:<uuid>   | shop:<shopId> | evidence:<caseId>
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_inventory` (
  `id`        BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
  `owner`     VARCHAR(64)       NOT NULL,
  `name`      VARCHAR(64)       NOT NULL,
  `amount`    INT               NOT NULL DEFAULT 1,
  `slot`      SMALLINT UNSIGNED NOT NULL,
  `metadata`  LONGTEXT          DEFAULT NULL,
  `created_at` TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_owner_slot` (`owner`, `slot`),
  KEY `idx_owner_name` (`owner`, `name`),
  KEY `idx_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  STASHES  ::  persistent named containers (lockers, evidence, properties)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_stashes` (
  `id`        INT UNSIGNED      NOT NULL AUTO_INCREMENT,
  `stash_id`  VARCHAR(64)       NOT NULL,
  `label`     VARCHAR(64)       NOT NULL,
  `slots`     SMALLINT UNSIGNED NOT NULL DEFAULT 50,
  `weight`    INT UNSIGNED      NOT NULL DEFAULT 100000,
  `owner`     VARCHAR(64)       DEFAULT NULL COMMENT 'job name / gang name / char id, NULL = public',
  `is_shared` TINYINT UNSIGNED  NOT NULL DEFAULT 0,
  `metadata`  LONGTEXT          DEFAULT NULL,
  `created_at` TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_stash` (`stash_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  VEHICLES
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_vehicles` (
  `id`            INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `plate`         VARCHAR(12)     NOT NULL,
  `model`         VARCHAR(48)     NOT NULL,
  `label`         VARCHAR(64)     DEFAULT NULL,
  `char_id`       INT UNSIGNED    DEFAULT NULL COMMENT 'NULL = not player owned',
  `garage`        VARCHAR(32)     NOT NULL DEFAULT 'legion',
  `vtype`         VARCHAR(16)     NOT NULL DEFAULT 'automobile' COMMENT 'automobile|bike|boat|heli|plane|truck',
  `state`         TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '0=out 1=stored 2=impounded',
  `impound_reason` VARCHAR(128)   DEFAULT NULL,
  `fuel`          FLOAT           NOT NULL DEFAULT 100,
  `engine_health` FLOAT           NOT NULL DEFAULT 1000,
  `body_health`   FLOAT           NOT NULL DEFAULT 1000,
  `mileage`       FLOAT           NOT NULL DEFAULT 0,
  `x`             FLOAT           DEFAULT NULL,
  `y`             FLOAT           DEFAULT NULL,
  `z`             FLOAT           DEFAULT NULL,
  `heading`       FLOAT           DEFAULT NULL,
  `mods`          LONGTEXT        DEFAULT NULL COMMENT 'JSON upgrade map',
  `colors`        LONGTEXT        DEFAULT NULL COMMENT 'JSON paint + livery',
  `extras`        LONGTEXT        DEFAULT NULL COMMENT 'JSON extras map',
  `neon`          LONGTEXT        DEFAULT NULL,
  `tyres`         LONGTEXT        DEFAULT NULL,
  `keys`          LONGTEXT        DEFAULT NULL COMMENT 'JSON array of char ids with spare keys',
  `purchase_price` INT UNSIGNED   DEFAULT NULL COMMENT 'what the owner paid (trade-in valuation)',
  `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_plate` (`plate`),
  KEY `idx_char` (`char_id`),
  KEY `idx_garage` (`garage`),
  KEY `idx_state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  GANGS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_gangs` (
  `id`          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `name`        VARCHAR(32)     NOT NULL,
  `label`       VARCHAR(64)     NOT NULL,
  `tag`         VARCHAR(8)      DEFAULT NULL,
  `colour`      VARCHAR(9)      DEFAULT '#8b5cf6',
  `bank`        INT             NOT NULL DEFAULT 0,
  `reputation`  INT             NOT NULL DEFAULT 0,
  `turf`        VARCHAR(64)     DEFAULT NULL,
  `created_at`  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_gang` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  BANKING / LEDGER  ::  every money movement is recorded (audit trail)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_transactions` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `char_id`       INT UNSIGNED    DEFAULT NULL,
  `account`       ENUM('cash','bank','black','savings') NOT NULL DEFAULT 'bank',
  `amount`        INT             NOT NULL,
  `balance_after` INT             DEFAULT NULL,
  `type`          VARCHAR(24)     NOT NULL DEFAULT 'transfer',
  `reason`        VARCHAR(160)    DEFAULT NULL,
  `actor`         VARCHAR(64)     DEFAULT NULL COMMENT 'who caused it (system name / char id)',
  `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_char` (`char_id`, `created_at`),
  KEY `idx_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  LICENCES  ::  driving / weapon / pilot etc, with points
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_licences` (
  `id`        INT UNSIGNED      NOT NULL AUTO_INCREMENT,
  `char_id`   INT UNSIGNED      NOT NULL,
  `name`      VARCHAR(32)       NOT NULL,
  `points`    TINYINT UNSIGNED  NOT NULL DEFAULT 0,
  `revoked`   TINYINT UNSIGNED  NOT NULL DEFAULT 0,
  `issued_by` VARCHAR(64)       DEFAULT NULL,
  `issued_at` TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_char_licence` (`char_id`, `name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  OUTFITS  ::  saved clothing presets per character
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_outfits` (
  `id`        INT UNSIGNED      NOT NULL AUTO_INCREMENT,
  `char_id`   INT UNSIGNED      NOT NULL,
  `name`      VARCHAR(48)       NOT NULL,
  `slot`      TINYINT UNSIGNED  DEFAULT NULL,
  `data`      LONGTEXT          NOT NULL,
  `created_at` TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_char` (`char_id`),
  UNIQUE KEY `uniq_char_name` (`char_id`, `name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  PHONE
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_phone_contacts` (
  `id`        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `char_id`   INT UNSIGNED  NOT NULL,
  `name`      VARCHAR(48)   NOT NULL,
  `number`    VARCHAR(16)   NOT NULL,
  `favourite` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_contact` (`char_id`, `number`),
  KEY `idx_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nx_phone_messages` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sender`        VARCHAR(16)   NOT NULL,
  `target`        VARCHAR(16)   NOT NULL,
  `message`       TEXT          NOT NULL,
  `is_read`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `created_at`    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_thread` (`sender`, `target`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nx_phone_notes` (
  `id`        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `char_id`   INT UNSIGNED  NOT NULL,
  `title`     VARCHAR(64)   NOT NULL DEFAULT 'Note',
  `body`      TEXT          NOT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  MODERATION
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_bans` (
  `id`          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `identifier`  VARCHAR(64)   NOT NULL COMMENT 'licence / discord / ip',
  `reason`      VARCHAR(255)  NOT NULL DEFAULT 'No reason provided',
  `banned_by`   VARCHAR(64)   NOT NULL DEFAULT 'Console',
  `expires_at`  TIMESTAMP     NULL DEFAULT NULL COMMENT 'NULL = permanent',
  `active`      TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `created_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_id_active` (`identifier`, `active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nx_warnings` (
  `id`          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `char_id`     INT UNSIGNED  DEFAULT NULL,
  `identifier`  VARCHAR(64)   NOT NULL,
  `reason`      VARCHAR(255)  NOT NULL,
  `issued_by`   VARCHAR(64)   NOT NULL,
  `created_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_ident` (`identifier`),
  KEY `idx_char` (`char_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nx_admin_logs` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor`       VARCHAR(64)   NOT NULL,
  `action`      VARCHAR(48)   NOT NULL,
  `target`      VARCHAR(64)   DEFAULT NULL,
  `details`     TEXT          DEFAULT NULL,
  `created_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_actor` (`actor`),
  KEY `idx_action` (`action`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  JOB / BUSINESS STATE  ::  money owed to employees, society balances
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_societies` (
  `id`        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `name`      VARCHAR(32)   NOT NULL,
  `label`     VARCHAR(64)   NOT NULL,
  `balance`   INT           NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_society` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  POLICE / EMS  ::  warrants, BOLOs, incidents and 911 calls
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_warrants` (
  `id`         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `char_id`    INT UNSIGNED  NOT NULL,
  `reason`     VARCHAR(160)  NOT NULL,
  `charges`    TEXT          DEFAULT NULL COMMENT 'free-form charge list',
  `fine`       INT           NOT NULL DEFAULT 0,
  `priority`   ENUM('low','normal','high') NOT NULL DEFAULT 'normal',
  `active`     TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `issued_by`  VARCHAR(64)   NOT NULL,
  `issued_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `cleared_by` VARCHAR(64)   DEFAULT NULL,
  `cleared_at` TIMESTAMP     NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_char_active` (`char_id`, `active`),
  KEY `idx_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nx_bolos` (
  `id`         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `plate`      VARCHAR(12)   DEFAULT NULL,
  `model`      VARCHAR(32)   DEFAULT NULL,
  `reason`     VARCHAR(160)  NOT NULL,
  `details`    TEXT          DEFAULT NULL,
  `priority`   ENUM('low','normal','high') NOT NULL DEFAULT 'normal',
  `active`     TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `issued_by`  VARCHAR(64)   NOT NULL,
  `issued_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`),
  KEY `idx_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nx_incidents` (
  `id`          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `code`        VARCHAR(16)   NOT NULL DEFAULT '10-13',
  `title`       VARCHAR(120)  NOT NULL,
  `details`     TEXT          DEFAULT NULL,
  `coords`      VARCHAR(80)   DEFAULT NULL COMMENT 'JSON {x,y,z}',
  `priority`    ENUM('low','normal','high') NOT NULL DEFAULT 'normal',
  `status`      ENUM('open','assigned','closed') NOT NULL DEFAULT 'open',
  `created_by`  VARCHAR(64)   NOT NULL,
  `created_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `closed_by`   VARCHAR(64)   DEFAULT NULL,
  `closed_at`   TIMESTAMP     NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_status` (`status`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nx_calls` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `caller`     VARCHAR(64)   DEFAULT NULL,
  `number`     VARCHAR(16)   DEFAULT NULL,
  `service`    ENUM('police','ambulance','mechanic','fire','other') NOT NULL DEFAULT 'police',
  `message`    VARCHAR(240)  NOT NULL,
  `coords`     VARCHAR(80)   DEFAULT NULL,
  `handled`    TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `handled_by` VARCHAR(64)   DEFAULT NULL,
  `created_at` TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_service` (`service`, `created_at`),
  KEY `idx_handled` (`handled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
--  MEDICAL  ::  patient charts written by EMS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `nx_medical` (
  `id`         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `char_id`    INT UNSIGNED  NOT NULL,
  `type`       ENUM('treatment','admission','revive','note','death') NOT NULL DEFAULT 'treatment',
  `title`      VARCHAR(120)  NOT NULL,
  `details`    TEXT          DEFAULT NULL,
  `medic`      VARCHAR(64)   NOT NULL,
  `created_at` TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_char` (`char_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
--  SEED DATA
-- ============================================================================

INSERT IGNORE INTO `nx_societies` (`name`, `label`, `balance`) VALUES
  ('police',   'Los Santos Police Department', 50000),
  ('ambulance','Pillbox Hill Medical Center',   50000),
  ('mechanic','Benny''s Motor Works',           25000),
  ('taxi',     'Downtown Cab Co.',              10000),
  ('realestate','Dynasty 8 Real Estate',        10000);

INSERT IGNORE INTO `nx_gangs` (`name`, `label`, `tag`, `colour`) VALUES
  ('vagos',      'Vagos',        'VGS', '#eab308'),
  ('ballas',     'Ballas',       'BLS', '#a855f7'),
  ('families',   'Families',     'FML', '#22c55e'),
  ('lostmc',     'The Lost MC',  'LMC', '#ef4444'),
  ('cartel',     'Madrazo Cartel','MDZ','#f97316');

INSERT IGNORE INTO `nx_stashes` (`stash_id`, `label`, `slots`, `weight`, `owner`, `is_shared`) VALUES
  ('police_locker',   'LSPD Locker Room',      80, 200000, 'police',    2),
  ('police_evidence', 'LSPD Evidence Locker',  120, 500000, 'police',   2),
  ('ambulance_locker','Pillbox Supply Room',   60, 150000, 'ambulance', 2),
  ('mechanic_locker', 'Benny''s Toolbox',      50, 120000, 'mechanic',  2);
