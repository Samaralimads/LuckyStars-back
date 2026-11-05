-- Lucky Stars database: structure only (no data). Use together with seed.sql on a fresh database.
-- For an existing database apply the files in Database/migrations/ instead.
--
-- Pairing codes (table `invitation`) are created by the trigger below when a user registers.

-- Dumped from a MariaDB 10.4 database (phpMyAdmin), data removed.

-- (stored procedure: see the end of this file)

-- --------------------------------------------------------

--
-- Table structure for table `activity`
--

CREATE TABLE `activity` (
  `id` binary(16) NOT NULL,
  `title` varchar(255) NOT NULL,
  `description` text NOT NULL,
  `budget` enum('€','€€','€€€') NOT NULL,
  `duration` int(11) NOT NULL,
  `is_indoor` tinyint(1) NOT NULL,
  `category_id` binary(16) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;


-- --------------------------------------------------------

--
-- Table structure for table `category`
--

CREATE TABLE `category` (
  `id` binary(16) NOT NULL,
  `name` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;


-- --------------------------------------------------------

--
-- Table structure for table `couple`
--

CREATE TABLE `couple` (
  `id` binary(16) NOT NULL,
  `partner1_id` binary(16) NOT NULL,
  `partner2_id` binary(16) DEFAULT NULL,
  `relationship_start_date` date NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;


-- --------------------------------------------------------

--
-- Table structure for table `favorite_activity`
--

CREATE TABLE `favorite_activity` (
  `id` binary(16) NOT NULL,
  `user_id` binary(16) NOT NULL,
  `activity_id` binary(16) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- (favorites are kept unique by the uq_user_activity key)

-- --------------------------------------------------------

--
-- Table structure for table `important_date`
--

CREATE TABLE `important_date` (
  `id` binary(16) NOT NULL,
  `user_id` binary(16) NOT NULL,
  `label` varchar(255) NOT NULL,
  `date` datetime NOT NULL,
  `reminder_enabled` tinyint(1) NOT NULL,
  `reminder_days_before` int(11) DEFAULT NULL,
  `repeat_yearly` tinyint(1) NOT NULL DEFAULT 0
) ;


-- --------------------------------------------------------

--
-- Table structure for table `invitation`
--

CREATE TABLE `invitation` (
  `id` binary(16) NOT NULL,
  `user_id` binary(16) NOT NULL,
  `invitation_code` char(6) NOT NULL,
  `code_used` tinyint(1) NOT NULL DEFAULT 0
) ;


-- --------------------------------------------------------

--
-- Table structure for table `password_reset`
--

CREATE TABLE `password_reset` (
  `id` binary(16) NOT NULL,
  `user_id` binary(16) NOT NULL,
  `code` char(6) NOT NULL,
  `expires_at` datetime NOT NULL,
  `used` tinyint(1) NOT NULL DEFAULT 0,
  `attempts` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;


-- --------------------------------------------------------

--
-- Table structure for table `planned_activity`
--

CREATE TABLE `planned_activity` (
  `id` binary(16) NOT NULL,
  `activity_id` binary(16) NOT NULL,
  `couple_id` binary(16) DEFAULT NULL,
  `planned_by_user_id` binary(16) NOT NULL,
  `proposed_date` datetime NOT NULL,
  `response_date` datetime DEFAULT NULL,
  `booking_status` enum('pending','accepted','rejected') NOT NULL,
  `reminder_enabled` tinyint(1) NOT NULL,
  `reminder_days_before` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `note` varchar(255) DEFAULT NULL
) ;


-- --------------------------------------------------------

--
-- Table structure for table `user`
--

CREATE TABLE `user` (
  `id` binary(16) NOT NULL,
  `first_name` varchar(50) NOT NULL,
  `birth_date` date NOT NULL,
  `email` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `profile_picture` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;


--
-- Triggers `user`
--
DELIMITER $$
CREATE TRIGGER `generate_invitation_code_for_new_user` AFTER INSERT ON `user` FOR EACH ROW BEGIN
    DECLARE new_code CHAR(6);
    DECLARE success BOOLEAN DEFAULT FALSE;

    WHILE NOT success DO
        SET new_code = LPAD(FLOOR(RAND() * 1000000), 6, '0');
        BEGIN
            DECLARE CONTINUE HANDLER FOR 1062 SET success = FALSE;
            SET success = TRUE;
            INSERT INTO invitation (id, user_id, invitation_code, code_used)
            VALUES (UNHEX(REPLACE(UUID(), '-', '')), NEW.id, new_code, FALSE);
        END;
    END WHILE;
END
$$
DELIMITER ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `activity`
--
ALTER TABLE `activity`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_activity_category` (`category_id`);

--
-- Indexes for table `category`
--
ALTER TABLE `category`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `couple`
--
ALTER TABLE `couple`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_couple_partner1` (`partner1_id`),
  ADD UNIQUE KEY `uq_couple_partner2` (`partner2_id`);

--
-- Indexes for table `favorite_activity`
--
ALTER TABLE `favorite_activity`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_user_activity` (`user_id`,`activity_id`),
  ADD KEY `fk_favorite_activity` (`activity_id`);

--
-- Indexes for table `important_date`
--
ALTER TABLE `important_date`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_important_date_user` (`user_id`);

--
-- Indexes for table `invitation`
--
ALTER TABLE `invitation`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_invitation_code` (`invitation_code`),
  ADD KEY `fk_invitation_user` (`user_id`);

--
-- Indexes for table `password_reset`
--
ALTER TABLE `password_reset`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_password_reset_user` (`user_id`);

--
-- Indexes for table `planned_activity`
--
ALTER TABLE `planned_activity`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_planned_activity_activity` (`activity_id`),
  ADD KEY `fk_planned_activity_couple` (`couple_id`),
  ADD KEY `fk_planned_activity_user` (`planned_by_user_id`);

--
-- Indexes for table `user`
--
ALTER TABLE `user`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Constraints for dumped tables
--

--
-- Constraints for table `activity`
--
ALTER TABLE `activity`
  ADD CONSTRAINT `fk_activity_category` FOREIGN KEY (`category_id`) REFERENCES `category` (`id`);

--
-- Constraints for table `couple`
--
ALTER TABLE `couple`
  ADD CONSTRAINT `fk_couple_partner1` FOREIGN KEY (`partner1_id`) REFERENCES `user` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_couple_partner2` FOREIGN KEY (`partner2_id`) REFERENCES `user` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `favorite_activity`
--
ALTER TABLE `favorite_activity`
  ADD CONSTRAINT `fk_favorite_activity` FOREIGN KEY (`activity_id`) REFERENCES `activity` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_favorite_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `important_date`
--
ALTER TABLE `important_date`
  ADD CONSTRAINT `fk_important_date_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `invitation`
--
ALTER TABLE `invitation`
  ADD CONSTRAINT `fk_invitation_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `password_reset`
--
ALTER TABLE `password_reset`
  ADD CONSTRAINT `fk_password_reset_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `planned_activity`
--
ALTER TABLE `planned_activity`
  ADD CONSTRAINT `fk_planned_activity_activity` FOREIGN KEY (`activity_id`) REFERENCES `activity` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_planned_activity_couple` FOREIGN KEY (`couple_id`) REFERENCES `couple` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_planned_activity_user` FOREIGN KEY (`planned_by_user_id`) REFERENCES `user` (`id`) ON DELETE CASCADE;

-- A couple can't be a person with themselves.
ALTER TABLE `couple`
  ADD CONSTRAINT `chk_couple_distinct_partners` CHECK (`partner2_id` IS NULL OR `partner1_id` <> `partner2_id`);

COMMIT;

--
-- Stored procedure used by POST /couples/join
--
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


/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
