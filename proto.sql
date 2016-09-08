DROP TABLE IF EXISTS packet;
DROP TABLE IF EXISTS device;
DROP TABLE IF EXISTS information_unit;
DROP TABLE IF EXISTS object_obs;
DROP TABLE IF EXISTS property_obs;
DROP TABLE IF EXISTS error;

-- *****************************************************************************
-- *****************************************************************************

CREATE TABLE packet(id INT NOT NULL PRIMARY KEY, epoch_ts DOUBLE(20, 10) NOT NULL,
                    sadr VARCHAR(17), dadr VARCHAR(17), invoke_id INT,
                    info VARCHAR(300));

CREATE TABLE device (counter INT NOT NULL AUTO_INCREMENT UNIQUE, 
                     epoch_ts DOUBLE(20, 10) NOT NULL, device_id INT UNIQUE,
                     model_name VARCHAR(100), object_name VARCHAR(100),
                     bacnet_adr VARCHAR(17), packet_id INT NOT NULL,
                     vendor VARCHAR(100), pics_file VARCHAR(100));

CREATE TABLE information_unit(counter INT NOT NULL AUTO_INCREMENT UNIQUE, 
                              epoch_ts DOUBLE(20, 10) NOT NULL,
                              message VARCHAR(100), object_name VARCHAR(100),
                              object_instance INT, property_name VARCHAR(100),
                              value VARCHAR(500));

CREATE TABLE object_obs(device_id INT NOT NULL, object_name VARCHAR(100) NOT NULL,
                        epoch_ts DOUBLE(20, 10),
                        is_present INT NOT NULL, packet_id INT NOT NULL,
                        packet_id_last_update INT,
                        PRIMARY KEY(device_id, object_name));

CREATE TABLE property_obs(device_id INT NOT NULL, object_name VARCHAR(100) NOT NULL,
                          property_name VARCHAR(100) NOT NULL,
                          epoch_ts DOUBLE(20, 10) NOT NULL, 
                          is_present INT NOT NULL, is_writeable INT NOT NULL,
                          packet_id INT NOT NULL, 
                          packet_id_last_update INT,
                          PRIMARY KEY(device_id, object_name, property_name));

CREATE TABLE error(counter INT NOT NULL AUTO_INCREMENT UNIQUE,
                   epoch_ts DOUBLE(20, 10) NOT NULL, reason VARCHAR(100),
                   invoke_id INT NOT NULL, service VARCHAR(100) NOT NULL,
                   class VARCHAR(100) NOT NULL, code VARCHAR(100) NOT NULL,
                   packet_id INT NOT NULL);
                   
CREATE VIEW objects_pics AS
SELECT T1.pics_file, T2.object_name, SUM(T2.is_present) AS is_present
FROM device T1 INNER JOIN object_obs T2 
WHERE T1.device_id = T2.device_id GROUP BY CONCAT(T1.pics_file, T2.object_name);


CREATE VIEW properties_pics AS
SELECT T1.pics_file, T2.object_name, T2.property_name, 
       SUM(T2.is_present) AS is_present, SUM(T2.is_writeable) AS is_writeable 
FROM device T1 INNER JOIN property_obs T2
WHERE T1.device_id = T2.device_id
GROUP BY CONCAT(T1.pics_file, T2.object_name, T2.property_name);

-- *****************************************************************************
-- *****************************************************************************

CREATE INDEX packet_sadr_index ON packet(sadr) USING HASH;
CREATE INDEX packet_dadr_index ON packet(dadr) USING HASH;
CREATE INDEX packet_epoch_ts_index ON packet(epoch_ts) USING HASH;
CREATE INDEX packet_invoke_id_index ON packet(invoke_id) USING HASH;
CREATE INDEX packet_id_index ON packet(id) USING BTREE;
CREATE INDEX device_adr_index ON device(bacnet_adr) USING HASH;
CREATE INDEX information_unit_epoch_ts_index ON information_unit(epoch_ts) USING HASH;
CREATE INDEX information_unit_message_index ON information_unit(message) USING HASH;
CREATE INDEX information_unit_obj_name_index ON information_unit(object_name) USING HASH;
CREATE INDEX information_unit_prop_name_index ON information_unit(property_name) USING HASH;
CREATE INDEX obj_obs_dev_id_index ON object_obs(device_id) USING HASH;
CREATE INDEX obj_obs_obj_name_index ON object_obs(object_name) USING HASH;
CREATE INDEX property_obs_dev_id_index ON property_obs(device_id) USING HASH;
CREATE INDEX property_obs_obj_name_index ON property_obs(object_name) USING HASH;
CREATE INDEX property_obs_prop_name_index ON property_obs(property_name) USING HASH;

-- *****************************************************************************
-- *****************************************************************************

DELIMITER $$
CREATE PROCEDURE GetPacketId(IN requested_epoch_ts DOUBLE(20, 10),
                             OUT requested_packet_id INT)
BEGIN
    SELECT id FROM packet
    WHERE epoch_ts = requested_epoch_ts ORDER BY id ASC LIMIT 1
    INTO requested_packet_id;
END$$

CREATE PROCEDURE GetSadrByEpochFromPacket(IN requested_epoch_ts DOUBLE(20, 10),
                                          OUT req_sadr VARCHAR(17))
BEGIN
    SELECT trim(sadr) FROM packet
    WHERE epoch_ts = requested_epoch_ts ORDER BY id ASC LIMIT 1
    INTO req_sadr;
    IF req_sadr = '' THEN
        SET req_sadr = NULL;
    END IF;
END$$



CREATE PROCEDURE GetDadrByEpochFromPacket(IN requested_epoch_ts DOUBLE(20, 10),
                                          OUT req_dadr VARCHAR(17))
BEGIN
    SELECT trim(dadr) FROM packet
    WHERE epoch_ts = requested_epoch_ts ORDER BY id ASC LIMIT 1
    INTO req_dadr;
    IF req_dadr = '' THEN
        SET req_dadr = NULL;
    END IF;
END$$



CREATE PROCEDURE GetDevIdByBACAdr(IN sadr VARCHAR(17),
                                  OUT dev_id INT)
BEGIN
    SELECT device_id
    FROM device
    WHERE bacnet_adr = sadr LIMIT 1
    INTO dev_id;
END$$


CREATE PROCEDURE GetDevIdByEpoch(IN requested_epoch_ts DOUBLE(20, 10),
                                 OUT dev_id INT)
BEGIN
    SELECT TRIM(SUBSTRING(info, 
                         LOCATE('device,', info)+7,
                         (LOCATE(' ', info, LOCATE('device,', info))-(LOCATE('device,', info)+7))))
    FROM packet
    WHERE epoch_ts = requested_epoch_ts LIMIT 1
    INTO dev_id;
END$$



CREATE PROCEDURE AmountObjObs(IN device_id INT, IN object_name VARCHAR(100),
                              OUT amount INT)
BEGIN
    SELECT COUNT(*) FROM object_obs
    WHERE object_obs.device_id = device_id AND
          object_obs.object_name = object_name
    INTO amount;
END$$



CREATE PROCEDURE AmountPropObs(IN device_id INT, IN object_name VARCHAR(100),
                               IN property_name VARCHAR(100),
                               OUT amount INT)
BEGIN
    SELECT COUNT(*) FROM property_obs
    WHERE property_obs.device_id = device_id AND
          property_obs.object_name = object_name AND
          property_obs.property_name = property_name
    INTO amount;
END$$



CREATE PROCEDURE IncObjectObsPresence(IN device_identifier INT, 
                                      IN epoch_ts DOUBLE(20,10),
                                      IN object_name VARCHAR(100))
BEGIN
    CALL GetPacketId(epoch_ts, @requested_packet_id);
                
    -- Check if entry already exists in the "object_obs" table
    CALL AmountObjObs(device_identifier, object_name, @amount);
    IF @amount > 0 THEN -- Yes, then update the value
        UPDATE object_obs SET is_present = (is_present+1),
                              packet_id_last_update = @requested_packet_id
            WHERE object_obs.device_id = device_identifier AND 
                  object_obs.object_name = object_name;
    ELSE                -- No, then create a new record
        INSERT IGNORE INTO object_obs(epoch_ts, device_id, object_name, 
                                      is_present, packet_id)
                  values (epoch_ts, device_identifier, object_name,
                          1, @requested_packet_id);
    END IF;
END$$



CREATE PROCEDURE DecObjectObsPresence(IN device_identifier INT, 
                                      IN epoch_ts DOUBLE(20,10),
                                      IN object_name VARCHAR(100))
BEGIN
    CALL GetPacketId(epoch_ts, @requested_packet_id);
    
    -- Check if entry already exists in the "object_obs" table
    CALL AmountObjObs(device_identifier, object_name, @amount);
    
    IF @amount > 0 THEN -- Yes, then update the value
        -- object_obs.is_present--
        UPDATE object_obs SET is_present = (is_present-1),
                              packet_id_last_update = @requested_packet_id 
            WHERE object_obs.device_id = device_identifier AND
                  object_obs.object_name = object_name;
    ELSE                -- No, then create a new record
        INSERT IGNORE INTO object_obs(epoch_ts, device_id, object_name, 
                                      is_present, packet_id)
               values (epoch_ts, device_identifier, object_name,
                       -1, @requested_packet_id);
    END IF;
END$$



CREATE PROCEDURE IncPropertyObsPresence(IN device_identifier INT, 
                                        IN epoch_ts DOUBLE(20,10),
                                        IN object_name VARCHAR(100),
                                        IN property_name VARCHAR(100))
BEGIN
    CALL GetPacketId(epoch_ts, @requested_packet_id);

    -- Check if entry already exists in the "property_obs" table
    CALL AmountPropObs(device_identifier, object_name, property_name, @amount);
    
    IF @amount > 0 THEN -- Yes, then update the value
        UPDATE property_obs SET is_present = (is_present+1),
                                packet_id_last_update = @requested_packet_id
        WHERE property_obs.device_id = device_identifier AND 
              property_obs.object_name = object_name AND
              property_obs.property_name = property_name;
    ELSE                -- No, then create a new record
        INSERT IGNORE INTO property_obs(device_id, object_name,
                                    epoch_ts, property_name,
                                    is_present, is_writeable,
                                    packet_id)
                 values(device_identifier, object_name, epoch_ts, property_name,
                        1, 0, @requested_packet_id);
    END IF;
END$$



CREATE PROCEDURE DecPropertyObsPresence(IN device_identifier INT, 
                                        IN epoch_ts DOUBLE(20,10),
                                        IN object_name VARCHAR(100),
                                        IN property_name VARCHAR(100))
BEGIN
    CALL GetPacketId(epoch_ts, @requested_packet_id);

    -- Check if entry already exists in the "property_obs" table
    CALL AmountPropObs(device_identifier, object_name, property_name, @amount);
    
    IF @amount > 0 THEN -- Yes, then update the value
        UPDATE property_obs SET is_present = (is_present-1),
                                packet_id_last_update = @requested_packet_id
        WHERE property_obs.device_id = device_identifier AND 
              property_obs.object_name = object_name AND
              property_obs.property_name = property_name;
    ELSE                -- No, then create a new record
        INSERT IGNORE INTO property_obs(device_id, object_name,
                                    epoch_ts, property_name,
                                    is_present, is_writeable,
                                    packet_id)
                 values(device_identifier, object_name, epoch_ts, property_name,
                        -1, 0, @requested_packet_id);
    END IF;
END$$



CREATE PROCEDURE IncPropertyObsWritability(IN device_identifier INT, 
                                           IN epoch_ts DOUBLE(20,10),
                                           IN object_name VARCHAR(100),
                                           IN property_name VARCHAR(100))
BEGIN
    CALL GetPacketId(epoch_ts, @requested_packet_id);

    -- Check if entry already exists in the "property_obs" table
    CALL AmountPropObs(device_identifier, object_name, property_name, @amount);
    
    IF @amount > 0 THEN -- Yes, then update the value
        UPDATE property_obs SET is_writeable = (is_writeable+1),
                                packet_id_last_update = @requested_packet_id
            WHERE property_obs.device_id = device_identifier AND 
                  property_obs.object_name = object_name AND
                  property_obs.property_name = property_name;
    ELSE                -- No, then create a new record
        INSERT IGNORE INTO property_obs(device_id, object_name,
                                    epoch_ts, property_name,
                                    is_present, is_writeable,
                                    packet_id)
                 values(device_identifier, object_name, epoch_ts, property_name,
                        0, 1, @requested_packet_id);
    END IF;
END$$



CREATE PROCEDURE DecPropertyObsWritability(IN device_identifier INT, 
                                           IN epoch_ts DOUBLE(20,10),
                                           IN object_name VARCHAR(100),
                                           IN property_name VARCHAR(100))
BEGIN
    CALL GetPacketId(epoch_ts, @requested_packet_id);

    -- Check if entry already exists in the "property_obs" table
    CALL AmountPropObs(device_identifier, object_name, property_name, @amount);
    
    IF @amount > 0 THEN -- Yes, then update the value
        UPDATE property_obs SET is_writeable = (is_writeable-1),
                                is_present = (is_present+1),
                                packet_id_last_update = @requested_packet_id
            WHERE property_obs.device_id = device_identifier AND 
                  property_obs.object_name = object_name AND
                  property_obs.property_name = property_name;
    ELSE                -- No, then create a new record
        INSERT IGNORE INTO property_obs(device_id, object_name,
                                    epoch_ts, property_name,
                                    is_present, is_writeable,
                                    packet_id)
                 values(device_identifier, object_name, epoch_ts, property_name,
                        1, -1, @requested_packet_id);
    END IF;
END$$



CREATE PROCEDURE InsertObjectTypesSupported(IN device_identifier INT,
                                            IN epoch_ts DOUBLE(20,10),
                                            IN whole_string VARCHAR(500))
BEGIN
    DECLARE remain_str VARCHAR (500);
    DECLARE object_str VARCHAR (100);
    DECLARE boolean_status VARCHAR (1);
    DECLARE start_limit TINYINT;
    DECLARE end_limit TINYINT;
    DECLARE equal_pos TINYINT;
    DECLARE bracket_pos TINYINT;
    DECLARE space_pos TINYINT;
    
    SET remain_str = whole_string;
    
    label1: WHILE remain_str REGEXP '=' DO
        SET equal_pos = LOCATE('=', remain_str);
        SET bracket_pos = LOCATE('[', remain_str);
        SET space_pos = LOCATE(' ', remain_str);
        
        -- If it is the first object E.g. '"[analog_input=T, ...'
        IF bracket_pos != 0 AND bracket_pos < space_pos THEN
            SET start_limit = bracket_pos + 1;
        ELSE
            SET start_limit = space_pos + 1;
        END IF;
                
        SET end_limit = equal_pos - start_limit;
        SET object_str = REPLACE(SUBSTRING(remain_str, start_limit, end_limit), '_', '-');

        -- Bro logs could add typos in object names. E.g. "file_"
        IF SUBSTRING(object_str, -1) = '-' THEN
	        SET object_str = SUBSTRING(object_str, 1, LENGTH(object_str)-1);
    	END IF;
        
        -- INSERT IGNORE INTO object(object_name) VALUES(object_str);
        SET boolean_status = SUBSTRING(remain_str, equal_pos+1, 1);
        IF boolean_status = 'T' THEN
            CALL IncObjectObsPresence(device_identifier, epoch_ts, object_str);
        -- ELSE -- ELSE boolean_status must be an 'F'
        ELSEIF boolean_status = 'F' THEN
            CALL DecObjectObsPresence(device_identifier, epoch_ts, object_str);
        END IF;
          
        SET remain_str = SUBSTRING(remain_str, end_limit + start_limit + 1);
    END WHILE label1;
END $$

DELIMITER ;

-- *****************************************************************************
-- *****************************************************************************

DELIMITER //
CREATE TRIGGER set_adr
BEFORE INSERT ON device
FOR EACH ROW
BEGIN
    CALL GetPacketId(NEW.epoch_ts, @packet_id_tmp);
    CALL GetSadrByEpochFromPacket(NEW.epoch_ts, @bacnet_adr_tmp);

    IF @packet_id_tmp IS NOT NULL THEN
        -- New records are ok even without bacnet_adr
        SET NEW.packet_id = @packet_id_tmp;
        SET NEW.bacnet_adr = @bacnet_adr_tmp;
    END IF;
END; //



CREATE TRIGGER affirmative_observations
BEFORE INSERT ON information_unit
FOR EACH ROW
BEGIN
    DECLARE _device_id INT;

    -- Check for:
    -- 1) PDU: COMPLEX_ACK   Service: ReadProperty[Multiple]
    -- 2) PDU: CONF_SERV     Service: ConfirmedCOVNotification
    -- 3) PDU: UNCONF_SERV   Service: I-Am
    IF trim(NEW.message) = 'ReadProperty_ACK' OR 
       trim(NEW.message) = 'ReadPropertyMultiple_ACK' OR 
       trim(NEW.message) = 'ConfirmedCOVNotification_Request' OR 
       trim(NEW.message) = 'I_Am_Request' 
    THEN
        IF trim(NEW.object_name) = 'device' THEN
            SET _device_id = NEW.object_instance;
            -- Update information about devices
            IF NEW.property_name = 'vendor-identifier' THEN
                UPDATE device SET vendor = REPLACE(NEW.value, '_', ' ')
                              WHERE device.device_id = NEW.object_instance;
            ELSEIF NEW.property_name = 'model-name' THEN
                UPDATE device SET model_name = NEW.value
                              WHERE device.device_id = NEW.object_instance;
            ELSEIF NEW.property_name = 'object-name' THEN
                UPDATE device SET object_name = NEW.value
                              WHERE device.device_id = NEW.object_instance;
            ELSEIF NEW.property_name = 'protocol-object-types-supported' THEN
                CALL InsertObjectTypesSupported(_device_id,
                                                NEW.epoch_ts,
                                                NEW.value);
            END IF;
            -- End of devices information update
        ELSE
            CALL GetSadrByEpochFromPacket(NEW.epoch_ts, @bacnet_adr);
            CALL GetDevIdByBACAdr(@bacnet_adr, @device_identifier);
            SET _device_id = @device_identifier;
        END IF;
        -- ------------------------------------------------
        IF trim(NEW.message) = 'ConfirmedCOVNotification_Request' AND 
           _device_id IS NULL THEN
            CALL GetDevIdByEpoch(NEW.epoch_ts, @device_identifier);
            SET _device_id = @device_identifier;
        END IF;
        -- ------------------------------------------------
        -- ------------------------------------------------
        IF _device_id IS NOT NULL THEN
            CALL IncObjectObsPresence(_device_id, NEW.epoch_ts, 
                                      trim(NEW.object_name));
            CALL IncPropertyObsPresence(_device_id, NEW.epoch_ts,
                                        trim(NEW.object_name), 
                                        trim(NEW.property_name));
        END IF;
        -- ------------------------------------------------
    -- ****************************************************
    ELSEIF trim(NEW.message) = 'ReadPropertyMultiple_Request'
    THEN
        CALL GetDadrByEpochFromPacket(NEW.epoch_ts, @bacnet_adr);
        CALL GetDevIdByBACAdr(@bacnet_adr, @device_identifier);
        SET _device_id = @device_identifier;
        -- ------------------------------------------------
        IF _device_id IS NOT NULL THEN
            CALL IncObjectObsPresence(_device_id, NEW.epoch_ts, 
                                      trim(NEW.object_name));
            CALL IncPropertyObsPresence(_device_id, NEW.epoch_ts,
                                        trim(NEW.object_name),
                                        trim(NEW.property_name));
        END IF;
        -- ------------------------------------------------
    -- END IF;
    -- ****************************************************    
    -- Are the properties writeable??
    ELSEIF trim(NEW.message) = 'WriteProperty_Request' OR
           trim(NEW.message) = 'WritePropertyMultiple_Request'
    THEN
        IF trim(NEW.object_name) = 'device' THEN
            SET _device_id = NEW.object_instance;            
        ELSE
            CALL GetDadrByEpochFromPacket(NEW.epoch_ts, @bacnet_adr);
            CALL GetDevIdByBACAdr(@bacnet_adr, @device_identifier);
            SET _device_id = @device_identifier;
        END IF;
        -- ------------------------------------------------
        IF _device_id IS NOT NULL THEN
            CALL IncObjectObsPresence(_device_id, NEW.epoch_ts,
                                      trim(NEW.object_name));
            CALL IncPropertyObsWritability(_device_id, NEW.epoch_ts,
                                           trim(NEW.object_name),
                                           trim(NEW.property_name));
        END IF;
        --  ------------------------------------------------   
    END IF;
END; //

DELIMITER ;
DELIMITER //
CREATE TRIGGER negative_observations
BEFORE INSERT ON error
FOR EACH ROW
BEGIN
    DECLARE _request_epoch_ts DOUBLE(20, 10);
    DECLARE _object_name VARCHAR(100);
    DECLARE _property_name VARCHAR(100);
    DECLARE _object_instance INT;
    DECLARE _matching_info_units INT;
    DECLARE _ack_info_units INT;

    -- Fill in the packet_id
    CALL GetPacketId(NEW.epoch_ts, @error_packet_id);
    SET NEW.packet_id = @error_packet_id;

    
        
    -- 1) Get sadr from error packet using epoch_ts
    CALL GetSadrByEpochFromPacket(NEW.epoch_ts, @error_bacnet_sadr);
    -- 2) Get device_id from device using sadr
    CALL GetDevIdByBACAdr(@error_bacnet_sadr, @error_device_id);
    
    -- *************************************************************************
    IF NEW.code = 'unknown-property' AND (NEW.service = 'readProperty' OR
                                          NEW.service = 'subscribeCOV' OR
                                          NEW.service = 'writeProperty')
    THEN    
        -- There might not be a sadr in the error packet if "device" is in
        -- the request.        
        IF @error_bacnet_sadr IS NULL THEN
            -- 1.2) Get request epoch_ts using: packet_id(<) invoke_id(=)
            SELECT epoch_ts FROM packet WHERE packet.invoke_id = NEW.invoke_id AND
                                              packet.id < NEW.packet_id AND
                                              (NEW.epoch_ts - packet.epoch_ts) < 0.15
                        ORDER BY id DESC LIMIT 1 INTO _request_epoch_ts;
            -- 1.3) Get the requested object
            SELECT object_name, object_instance, property_name FROM information_unit
                WHERE information_unit.epoch_ts = _request_epoch_ts
                LIMIT 1
                INTO _object_name, _object_instance, _property_name;
                
            IF _object_name = 'device' THEN
                -- The object DOES exist!
                CALL IncObjectObsPresence(_object_instance, NEW.epoch_ts, 
                                          _object_name);
                CALL DecPropertyObsPresence(_object_instance, NEW.epoch_ts,
                                            _object_name, _property_name);
            END IF;
        -- An attribute from an object different than device triggered the error
        ELSE
            -- 2.3) Get request epoch_ts using: packet_id(<) invoke_id(=) sadr(=dadr)
            SELECT epoch_ts FROM packet WHERE packet.invoke_id = NEW.invoke_id AND
                                          packet.dadr = @error_bacnet_sadr AND 
                                          packet.id < NEW.packet_id AND
                                          (NEW.epoch_ts - packet.epoch_ts) < 0.15
                        ORDER BY id DESC LIMIT 1 INTO _request_epoch_ts;
            -- 2.4) Get the requested object
            SELECT object_name, property_name FROM information_unit
                WHERE information_unit.epoch_ts = _request_epoch_ts
                LIMIT 1
                INTO _object_name, _property_name;                
            
            -- The object DOES exist!
            CALL IncObjectObsPresence(@error_device_id, NEW.epoch_ts, 
                                      _object_name);
            CALL DecPropertyObsPresence(@error_device_id, NEW.epoch_ts,
                                        _object_name, _property_name);
        END IF;
    
    -- *************************************************************************
    ELSEIF NEW.code = 'write-access-denied'
    THEN
        -- 3) Get request epoch_ts using: packet_id(<) invoke_id(=) sadr(=dadr)
        SELECT epoch_ts FROM packet WHERE packet.invoke_id = NEW.invoke_id AND
                                      packet.dadr = @error_bacnet_sadr AND 
                                      packet.id < NEW.packet_id AND
                                      (NEW.epoch_ts - packet.epoch_ts) < 0.15
                    ORDER BY id DESC LIMIT 1 INTO _request_epoch_ts;
        -- 4) Get the requested object
        SELECT object_name, property_name FROM information_unit
                WHERE information_unit.epoch_ts = _request_epoch_ts
                LIMIT 1
                INTO _object_name, _property_name;
                
        -- The object DOES exist! But it was inserted during the REQUEST
        -- CALL IncObjectObsPresence(@error_device_id, NEW.epoch_ts, 
        --                          _object_name);

        CALL DecPropertyObsWritability(@error_device_id, NEW.epoch_ts,
                                        _object_name, _property_name);
    -- END IF;
    
    -- *************************************************************************
    ELSEIF NEW.service = 'readPropertyMultiple_(property)' THEN
        -- 3) get request epoch_ts using: packet_id(<) invoke_id(=) sadr(=dadr)
        SELECT epoch_ts FROM packet WHERE packet.invoke_id = NEW.invoke_id AND
                                          packet.id < NEW.packet_id AND
                                          (NEW.epoch_ts - packet.epoch_ts) < 0.15
                        ORDER BY id DESC LIMIT 1 INTO _request_epoch_ts;
        
        IF _request_epoch_ts IS NOT NULL THEN
            -- COULD BE MORE THAN 1!!!!
            SELECT COUNT(*) FROM information_unit
            WHERE information_unit.epoch_ts = _request_epoch_ts
            INTO _matching_info_units;
            
            WHILE _matching_info_units > 0 DO
                SET _matching_info_units = (_matching_info_units-1);
            
                SELECT object_name, property_name FROM information_unit
                    WHERE information_unit.epoch_ts = _request_epoch_ts
                    LIMIT _matching_info_units, 1
                    INTO _object_name, _property_name;
                    
                -- Fix of the ReadPropertyMultiple problem.
                -- E.g. Some successful reads and at least 1 unknown problem.
                SELECT COUNT(*) FROM information_unit
                    WHERE information_unit.epoch_ts = NEW.epoch_ts AND
                       information_unit.message = "ReadPropertyMultiple_ACK" AND
                       information_unit.object_name = _object_name AND
                       information_unit.property_name = _property_name
                    INTO _ack_info_units;


                -- Decrement only those objects whitout ACK in information_unit
                IF NEW.code = 'unknown-property' AND _ack_info_units = 0 THEN
                    -- The object DOES exist!
                    CALL IncObjectObsPresence(@error_device_id, NEW.epoch_ts, 
                                              _object_name);
                    CALL DecPropertyObsPresence(@error_device_id, NEW.epoch_ts,
                                        _object_name, _property_name);
                END IF;
            END WHILE;
        END IF;
    END IF;
END; //
DELIMITER ;

