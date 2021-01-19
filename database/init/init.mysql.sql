-- Create logs table

CREATE TABLE IF NOT EXISTS `logs` (
	`uid` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `uuid` CHAR(36) NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
    `ts` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `type` VARCHAR(10) NOT NULL,
	`message` VARCHAR(50) NOT NULL,
	PRIMARY KEY (`uid`),
	INDEX `UNQ` (`uuid` ASC, `ts` ASC) VISIBLE
) COLLATE='latin1_swedish_ci';

-- Create uuid_v4 function

DROP function IF EXISTS `uuid_v4`;

DELIMITER $$
CREATE FUNCTION uuid_v4()
    RETURNS CHAR(36) DETERMINISTIC
BEGIN
    -- 1th and 2nd block are made of 6 random bytes
    SET @h1 = HEX(RANDOM_BYTES(4));
    SET @h2 = HEX(RANDOM_BYTES(2));

    -- 3th block will start with a 4 indicating the version, remaining is random
    SET @h3 = SUBSTR(HEX(RANDOM_BYTES(2)), 2, 3);

    -- 4th block first nibble can only be 8, 9 A or B, remaining is random
    SET @h4 = CONCAT(HEX(FLOOR(ASCII(RANDOM_BYTES(1)) / 64)+8),
                SUBSTR(HEX(RANDOM_BYTES(2)), 2, 3));

    -- 5th block is made of 6 random bytes
    SET @h5 = HEX(RANDOM_BYTES(6));

    -- Build the complete UUID
    RETURN LOWER(CONCAT(
        @h1, '-', @h2, '-4', @h3, '-', @h4, '-', @h5
    ));
END$$

DELIMITER ;

-- Create settings table

CREATE TABLE IF NOT EXISTS `settings` (
	`uid` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `uuid` CHAR(36) NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
	`mainkey` VARCHAR(50) NOT NULL,
	`subkey` VARCHAR(50) NOT NULL,
	`value` JSON NOT NULL,
	PRIMARY KEY (`uid`),
	UNIQUE INDEX `UNQ` (`uuid`, `mainkey`, `subkey`)
) COLLATE='latin1_swedish_ci';

-- Insert default settings into settings table

REPLACE INTO `settings` ( `mainkey`, `subkey`, `value` ) 
VALUES 
	( 'core', 'build', '1' ),
	( 'core', 'language', '"en"' );

-- Create default whitelist entries

REPLACE INTO `settings` ( `mainkey`, `subkey`, `value` ) 
VALUES 
	( 'whitelist', '52.32.178.7', '{"ip":"52.32.178.7", "description":"TradingView Server Address","canDelete":0}'),
	( 'whitelist', '54.218.53.128', '{"ip":"54.218.53.128", "description":"TradingView Server Address","canDelete":0}'),
	( 'whitelist', '34.212.75.30', '{"ip":"34.212.75.30", "description":"TradingView Server Address","canDelete":0}'),
	( 'whitelist', '52.89.214.238', '{"ip":"52.89.214.238", "description":"TradingView Server Address","canDelete":0}'),
	( 'whitelist', '127.0.0.1', '{"ip":"127.0.0.1", "description":"localhost","canDelete":0}');

-- Create users table if required		

CREATE TABLE IF NOT EXISTS `users` (
	`uid` INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`uuid` CHAR(38) NOT NULL,
	`email` VARCHAR(100) NOT NULL,
	`enabled` BOOL NOT NULL DEFAULT true,
	`last` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `token` JSON NULL DEFAULT NULL,
    `expiry` BIGINT NULL DEFAULT NULL,
	PRIMARY KEY (`uid`),
	UNIQUE INDEX `UNQ_UUID` (`uuid`),
	UNIQUE INDEX `UNQ_EMAIL` (`email`),
	INDEX `IDX_UUID` (`uuid` ASC) VISIBLE,
	INDEX `IDX_EMAIL` (`email` ASC) VISIBLE
) COLLATE='latin1_swedish_ci';    

DROP TRIGGER IF EXISTS `users_before_insert`;
DROP TRIGGER IF EXISTS `users_before_update`;

DELIMITER $$
CREATE TRIGGER `users_before_insert` BEFORE INSERT ON `users`
FOR EACH ROW
  IF new.uuid IS NULL
  THEN
    SET new.uuid = uuid_v4();
  END IF$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER `users_before_update` BEFORE UPDATE ON `users`
FOR EACH ROW
  SET new.last = CURRENT_TIMESTAMP;
$$
DELIMITER ;

-- Create multiuser_enable procedure

DROP PROCEDURE IF EXISTS `multiuser_enable`;

DELIMITER $$
CREATE PROCEDURE `multiuser_enable` (
	IN email VARCHAR(100),
    IN url VARCHAR(100),
    IN clientid VARCHAR(100),
    IN secret VARCHAR(100)
)
BEGIN

	-- Configure master user
    SELECT COUNT(*) INTO @checkuuid FROM `settings` WHERE mainkey='core' AND subkey='uuid';
	IF @checkuuid = 0 THEN
		SET @uuid = uuid_v4();
		INSERT INTO `settings` (uuid, mainkey, subkey, value) VALUES ('00000000-0000-0000-0000-000000000000', 'core', 'uuid', CONCAT('"',@uuid,'"'));
	ELSE
		SELECT REPLACE(value,'"','') INTO @uuid FROM `settings` WHERE mainkey='core' AND subkey='uuid';
	END IF;
	UPDATE `settings` SET `uuid`='00000000-0000-0000-0000-000000000000' WHERE mainkey IN ('core','whitelist');
	UPDATE `settings` SET `uuid`=@uuid WHERE mainkey NOT IN ('core','whitelist') AND uuid IN ('00000000-0000-0000-0000-000000000000',NULL);
	REPLACE INTO `users` (uuid, email, enabled) VALUES (@uuid, email, true);
    
    -- Configure Google Auth settings
    REPLACE INTO `settings` (uuid, mainkey, subkey, value) 
    VALUES 
		('00000000-0000-0000-0000-000000000000','core', 'auth:clientid', CONCAT('"',clientid,'"')),
        ('00000000-0000-0000-0000-000000000000','core', 'auth:secret', CONCAT('"',secret,'"')),
        ('00000000-0000-0000-0000-000000000000','core', 'auth:url', CONCAT('"',url,'"'));
    
	-- Enable multi user mode
	REPLACE INTO `settings` (uuid, mainkey, subkey, value) VALUES ('00000000-0000-0000-0000-000000000000','core', 'multiuser:enabled','true');
		
END$$
DELIMITER ;

-- Create multiuser_disable procedure

DROP procedure IF EXISTS `multiuser_disable`;

DELIMITER $$
CREATE PROCEDURE `multiuser_disable` ()
BEGIN
	SELECT REPLACE(value,'"','') INTO @uuid FROM `settings` WHERE mainkey='core' AND subkey='uuid';
    IF @uuid IS NOT NULL THEN
		UPDATE `settings` SET `uuid`=@uuid WHERE mainkey NOT IN ('core','whitelist') AND uuid IN (@uuid);
	END IF;
	REPLACE INTO `settings` (uuid, mainkey, subkey, value) VALUES ('00000000-0000-0000-0000-000000000000','core', 'multiuser:enabled','false');
END$$

DELIMITER ;