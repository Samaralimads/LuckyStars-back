-- 001: security and pairing fixes, for an EXISTING database.
-- (A new database uses schema.sql, which already has all of this.)
--
-- BEFORE YOU RUN IT
--   1. Back up the database.
--   2. Check there are no duplicates, or step 2 below will fail. Both queries should return no rows:
--        SELECT partner1_id, COUNT(*) FROM couple GROUP BY partner1_id HAVING COUNT(*) > 1;
--        SELECT partner2_id, COUNT(*) FROM couple WHERE partner2_id IS NOT NULL GROUP BY partner2_id HAVING COUNT(*) > 1;
--      And this one too (a person that is in two couples, once on each side):
--        SELECT c1.partner1_id FROM couple c1 JOIN couple c2 ON c1.partner1_id = c2.partner2_id;
--
-- ORDER OF DEPLOYMENT
--   Run this file, then deploy the new backend straight away. The new backend needs the
--   `attempts` column, and the old backend can't call the new join procedure (it passes 3 arguments, not 2).

-- 1. Password reset codes lock after too many wrong guesses.
ALTER TABLE `password_reset` ADD COLUMN `attempts` INT NOT NULL DEFAULT 0 AFTER `used`;

-- 2. One couple per person, and nobody is a couple with themselves.
--    (The unique keys also serve the foreign keys, so the old plain keys can go in the same statement.)
ALTER TABLE `couple`
  ADD UNIQUE KEY `uq_couple_partner1` (`partner1_id`),
  ADD UNIQUE KEY `uq_couple_partner2` (`partner2_id`),
  DROP INDEX `fk_couple_partner1`,
  DROP INDEX `fk_couple_partner2`;

ALTER TABLE `couple`
  ADD CONSTRAINT `chk_couple_distinct_partners` CHECK (`partner2_id` IS NULL OR `partner1_id` <> `partner2_id`);

-- 3. `invitation_code` had the same unique index twice.
ALTER TABLE `invitation` DROP INDEX `invitation_code`;

-- 4. Not needed any more.
--    - The favorites trigger repeated the unique key uq_user_activity (the backend handles that error).
--    - days_until_next_anniversary was not called anywhere (and was a day off after Feb 28 in leap years).
DROP TRIGGER IF EXISTS `before_insert_favorite`;
DROP FUNCTION IF EXISTS `days_until_next_anniversary`;

-- 5. Safer join procedure: rejects your own code and people already in a couple, locks the code
--    while it is used, and undoes everything on failure. It no longer takes a start date
--    (the couple already has the one user 1 entered).
DROP PROCEDURE IF EXISTS `create_couple_from_invitation`;

DELIMITER $$
CREATE PROCEDURE `create_couple_from_invitation` (IN `entered_code` VARCHAR(10), IN `user2_id_str` CHAR(36))
BEGIN
    DECLARE user1_bin BINARY(16) DEFAULT NULL;
    DECLARE user2_bin BINARY(16);
    DECLARE couple_id_bin BINARY(16) DEFAULT NULL;

    -- Any failure (including the SIGNALs below) undoes everything and is passed on to the caller.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET user2_bin = UNHEX(REPLACE(user2_id_str, '-', ''));

    START TRANSACTION;

    -- FOR UPDATE: two people entering the same code at the same moment can't both get through.
    SELECT user_id INTO user1_bin
    FROM invitation
    WHERE invitation_code = entered_code
      AND code_used = FALSE
    LIMIT 1
    FOR UPDATE;

    IF user1_bin IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid or already used invitation code';
    END IF;

    IF user1_bin = user2_bin THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'You cannot join your own invitation';
    END IF;

    IF EXISTS (SELECT 1 FROM couple WHERE partner1_id = user2_bin OR partner2_id = user2_bin) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'You are already in a couple';
    END IF;

    -- The couple user 1 created while setting up (the anniversary date is already on it).
    SELECT id INTO couple_id_bin
    FROM couple
    WHERE partner1_id = user1_bin
      AND partner2_id IS NULL
    LIMIT 1
    FOR UPDATE;

    IF couple_id_bin IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No open couple found for this invitation';
    END IF;

    UPDATE couple
    SET partner2_id = user2_bin
    WHERE id = couple_id_bin;

    UPDATE invitation
    SET code_used = TRUE
    WHERE invitation_code = entered_code;

    COMMIT;
END$$
DELIMITER ;
