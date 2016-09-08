#!/bin/bash
start=`date +'%H:%M:%S'`;
echo -e "\e[01;33mStart: $start\e[00m";

# DB connection details (MySQL)
DATABASE="";
USER="";
PASS="";
HOST="";

# Pool of pdf (and XML) PICS files
PICS_DIR="/path/to/dir";

# define is_file_exits function 
# $f -> store argument passed to the script
is_file_exits(){
	local f="$1"
	[[ -f "$f" ]] && return 0 || return 1
}


# Creates a gnuplot script, generates a .ps file and deletes the script.
function create_dev_plot() {
    #echo "set term png" >> dev.pg;
    echo "set terminal postscript eps enhanced" >> dev.pg;
    echo "set output '$4'" >> dev.pg;
    echo "set size 0.8, 0.8" >> dev.pg;
    echo "set logscale x" >> dev.pg;
    echo "set xrange [1:]" >> dev.pg;
    echo "set format x \"10^{%L}\"" >> dev.pg;
    echo "set xlabel '$2'" >> dev.pg;
    echo "set ylabel '$3'" >> dev.pg;
    echo "set style line 1 linecolor rgb '#ffa500' linetype 1 linewidth 2" >> dev.pg;
    echo "plot '$1' with lines linestyle 1 title ''" >> dev.pg;
    gnuplot dev.pg;
    rm dev.pg;
}



if [ "$#" -ne 1 ]; then
    echo -e "\e[00;31mpcap file required.\e[00m";
    exit 0;
fi


echo -e "\e[01;32m\nChecking Solr...\e[00m";
netstat -an | grep :8983
if [ $? == 1 ]; then
    echo -e "\e[00;31m\bDown :(\e[00m ";
fi



# Run Bro
echo -e "\e[01;32m\nRunning Bro...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    /path/to/bro -r "$1"  /path/to/hilti/bro/pac2/bacnet.evt /path/to/hilti/bro/pac2/bacnet_apdu.bro /path/to/hilti/bro/tests/pac2/bacnet/apdu.bro;
fi

# Run Wireshark to generate packets.csv
echo -e "\e[01;32m\nRunning tshark...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    tshark -r "$1" -n -Tfields -E header=y -E quote=d -E separator=',' -e frame.number -e frame.time_epoch -e bacnet.sadr_eth -e bacnet.dadr_eth -e bacapp.invoke_id -e _ws.col.Info > "$1.csv";
fi

# Remove comments in Bro logs
echo -e "\e[01;32m\nFormating logs...\e[00m"
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    if ( is_file_exits "bacnetapdu_errors.log" ) then
        grep -v '^#' bacnetapdu_errors.log > errors.csv;
        # Fix errors.log to adjust it to the table format
	sed -i 's/_, /\t/g' errors.csv;
    else
	echo -e "\e[00;31m\nNo bacnetapdu_errors.log found.\e[00m";
    fi
    if ( is_file_exits "bacnetapdu_information_units.log" ) then
        grep -v '^#' bacnetapdu_information_units.log > units.csv;
    else
	echo -e "\e[00;31m\nNo bacnetapdu_information_units.log found.\e[00m";
    fi
    if ( is_file_exits "bacnettest_devices.log" ) then
        grep -v -e '^#' bacnettest_devices.log > devices.csv;
    else
	echo -e "\e[00;31m\nNo bacnettest_devices.log found.\e[00m";
    fi
fi
# Set up database

echo -e "\e[01;32m\nRunning DB script...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then       
    mysql --user="$USER" --password="$PASS" --database="$DATABASE" --host="$HOST" < proto.sql;
fi

echo -e "\e[01;32m\nLoading packets into DB...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    mysql --user="$USER" --password="$PASS" --database="$DATABASE" --host="$HOST" --local-infile=1 --execute="LOAD DATA LOCAL INFILE '$1.csv' INTO TABLE packet FIELDS TERMINATED BY ',' ENCLOSED BY '\"' IGNORE 1 LINES;";
fi


echo -e "\e[01;32m\nLoading devices into DB...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    mysql --user="$USER" --password="$PASS" --database="$DATABASE" --host="$HOST" --local-infile=1 --execute="LOAD DATA LOCAL INFILE 'devices.csv' IGNORE INTO TABLE device (epoch_ts, device_id, model_name, object_name);";
fi


echo -e "\e[01;32m\nLoading information_units into DB...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    mysql --user="$USER" --password="$PASS" --database="$DATABASE" --host="$HOST" --local-infile=1 --execute="LOAD DATA LOCAL INFILE 'units.csv' INTO TABLE information_unit(epoch_ts, message, object_name, object_instance, property_name, value);";
fi

echo -e "\e[01;32m\nLoading errors into DB...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    mysql --user="$USER" --password="$PASS" --database="$DATABASE" --host="$HOST" --local-infile=1 --execute="LOAD DATA LOCAL INFILE 'errors.csv' INTO TABLE error(epoch_ts, reason, invoke_id, service, class, code);";
fi


echo -e "\e[01;32m\nCleaning Solr repository...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    curl http://localhost:8983/solr/abc/update/?commit=true -H "Content-Type: text/xml" --data-binary '<delete><query>*:*</query></delete>' -o /dev/null -s;
fi

echo -e "\e[01;32m\nLoading PICS into Solr...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    /path/to/solr/bin/post -c abc "$PICS_DIR"/*.pdf > /dev/null;
fi
    
echo -e "\e[01;32m\nFinding PICS for each device...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    ./match_pics.py $HOST $USER $PASS $DATABASE
fi

echo -e "\e[01;32m\nGenerating plots...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    # Get total packet count
    total_packets=`mysql --user="$USER" --password="$PASS" --database="$DATABASE" --host="$HOST" --execute="SELECT count(*) as '' FROM packet;"`
    
    mysql -N --user="$USER" --password="$PASS" --database="$DATABASE" --host="$HOST" --execute="SELECT packet_id, counter FROM device ORDER BY counter;" > "/tmp/devices-packets-$start.csv";
    last_y_value=`tail -n 1 "/tmp/devices-packets-$start.csv" | cut -f 2`;
    echo -e "$total_packets\t$last_y_value" >> "/tmp/devices-packets-$start.csv";
    grep "." "/tmp/devices-packets-$start.csv" >> "/tmp/devices-packets.csv";
    create_dev_plot "/tmp/devices-packets.csv" 'BACnet packets' 'Identified devices' 'devices.ps';
    rm "/tmp/devices-packets.csv";


    mysql -N --user="$USER" --password="$PASS" --database="$DATABASE" --host="$HOST" --execute="SELECT packet_id FROM object_obs ORDER BY epoch_ts;" > "/tmp/object-obs-$start.csv";
    len=`wc -l /tmp/object-obs-$start.csv | awk '{print $1}'`;
    seq $len > /tmp/counter.txt;
    paste "/tmp/object-obs-$start.csv" "/tmp/counter.txt" > "/tmp/object-obs.csv";
    last_y_value=`tail -n 1 "/tmp/object-obs.csv" | cut -f 2`;
    echo -e "$total_packets\t$last_y_value" >> "/tmp/object-obs.csv";
    grep "." "/tmp/object-obs.csv" > "/tmp/object-obs-final.csv";
    create_dev_plot '/tmp/object-obs-final.csv' 'BACnet packets' 'Identified BACnet objects' 'objects.ps'
    rm "/tmp/object-obs.csv" "/tmp/object-obs-final.csv" "/tmp/counter.txt";

    mysql -N --user="$USER" --password="$PASS" --database="$DATABASE" --host="$HOST" --execute="SELECT packet_id FROM property_obs ORDER BY epoch_ts;" > "/tmp/property-obs-$start.csv";
    len=`wc -l /tmp/property-obs-$start.csv | awk '{print $1}'`
    seq $len > /tmp/counter.txt
    paste "/tmp/property-obs-$start.csv" "/tmp/counter.txt" > "/tmp/property-obs.csv"
    last_y_value=`tail -n 1 "/tmp/property-obs.csv" | cut -f 2`;
    echo -e "$total_packets\t$last_y_value" >> "/tmp/property-obs.csv";
    grep "." "/tmp/property-obs.csv" > "/tmp/property-obs-final.csv";
    create_dev_plot '/tmp/property-obs-final.csv' 'BACnet packets' 'Identified BACnet properties' 'properties.ps'
    rm "/tmp/property-obs.csv" "/tmp/property-obs-final.csv" "/tmp/counter.txt";
fi

echo -e "\e[01;32m\nInterpreting PICS...\e[00m";
read -n1 -r -p "[s]kip, [any] to continue... " key
if [ "$key" != 's' ]; then
    ./Rule_Generator.py $HOST $USER $PASS $DATABASE > /dev/null;
fi

echo -e "";
echo -e "\e[01;32m\nDone!\e[00m";

finish=`date +'%H:%M:%S'`
echo -e "\e[01;33m\nFinish: $finish\e[00m"
# EOF


