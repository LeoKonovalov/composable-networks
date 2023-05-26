#!/bin/sh
BANKSY_HOME="/tmp/banksy$(date +%s)"
RANDOM_KEY="randombanksyvalidatorkey"
CHAIN_ID=banksy-testnet-3
DENOM=ppica
MAXBOND=50000000000000000000000

GENTX_FILE=$(find ./$CHAIN_ID/gentxs -iname "*.json")
LEN_GENTX=$(echo ${#GENTX_FILE})


if [ $LEN_GENTX -eq 0 ]; then
    echo "No new gentx file found."
else
    set -e

    echo "GentxFile::::"
    echo $GENTX_FILE

    echo "...........Init Banksy.............."

    git clone https://github.com/notional-labs/composable-testnet
    cd composable-testnet
    git checkout v2.3.4
    make build
    chmod +x ./build/banksyd

    ./build/banksyd keys add $RANDOM_KEY --keyring-backend test --home $BANKSY_HOME

    ./build/banksyd init --chain-id $CHAIN_ID validator --home $BANKSY_HOME

    echo "..........Fetching genesis......."
    rm -rf $BANKSY_HOME/config/genesis.json
    curl -s https://github.com/notional-labs/composable-networks/blob/main/banksy-testnet-3/pregenesis.json >$BANKSY_HOME/config/genesis.json

    # this genesis time is different from original genesis time, just for validating gentx.
    sed -i '/genesis_time/c\   \"genesis_time\" : \"2023-05-25T00:00:00Z\",' $BANKSY_HOME/config/genesis.json

    GENACC=$(cat ../$GENTX_FILE | sed -n 's|.*"delegator_address":"\([^"]*\)".*|\1|p')
    denomquery=$(jq -r '.body.messages[0].value.denom' ../$GENTX_FILE)
    amountquery=$(jq -r '.body.messages[0].value.amount' ../$GENTX_FILE)

    echo $GENACC
    echo $amountquery
    echo $denomquery

    # only allow $DENOM tokens to be bonded
    if [ $denomquery != $DENOM ]; then
        echo "invalid denomination"
        exit 1
    fi

    # limit the amount that can be bonded

    if [ $amountquery -gt $MAXBOND ]; then
        echo "bonded too much: $amountquery > $MAXBOND"
        exit 1
    fi

    ./build/banksyd add-genesis-account $RANDOM_KEY 100000000000000000000$DENOM --home $BANKSY_HOME \
        --keyring-backend test

    ./build/banksyd gentx $RANDOM_KEY 90000000000000000000$DENOM --home $BANKSY_HOME \
        --keyring-backend test --chain-id $CHAIN_ID

    cp ../$GENTX_FILE $BANKSY_HOME/config/gentx/

    echo "..........Collecting gentxs......."
    ./build/banksyd collect-gentxs --home $BANKSY_HOME
    sed -i '/persistent_peers =/c\persistent_peers = ""' $BANKSY_HOME/config/config.toml

    ./build/banksyd validate-genesis --home $BANKSY_HOME

    echo "..........Starting node......."
    ./build/banksyd start --home $BANKSY_HOME &

    sleep 1800s

    echo "...checking network status.."

    ./build/banksyd status --node http://localhost:26657

    echo "...Cleaning the stuff..."
    killall banksyd >/dev/null 2>&1
    rm -rf $BANKSY_HOME >/dev/null 2>&1
fi