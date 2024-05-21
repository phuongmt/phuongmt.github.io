
# Setting
MONIKER="jack688.init"  #ten Node

#######################
CHAIN_ID="initiation-1"
WALLET_NAME="jack688.init"
RPC_PORT="26657"
EXTERNAL_IP=$(wget -qO- eth0.me)
PROXY_APP_PORT="26658"
P2P_PORT="26656"
PPROF_PORT="6060"
API_PORT="1317"
GRPC_PORT="9090"
GRPC_WEB_PORT="9091"


# Set up environment variables
echo "export MONIKER=\"$MONIKER\"" >> ~/.bash_profile
echo "export CHAIN_ID=\"$CHAIN_ID\"" >> ~/.bash_profile
echo "export WALLET_NAME=\"$WALLET_NAME\"" >> ~/.bash_profile
echo "export RPC_PORT=\"$RPC_PORT\"" >> ~/.bash_profile
source ~/.bash_profile

# Download genesis.json
if [[ -f /root/.initia/config/genesis.json ]]; then
    rm -rf /root/.initia/config/genesis.json
fi

wget https://initia.s3.ap-southeast-1.amazonaws.com/initiation-1/genesis.json -O $HOME/.initia/config/genesis.json

## fast address book
wget https://initia.s3.ap-southeast-1.amazonaws.com/initiation-1/addrbook.json
mv addrbook.json ~/.initia/config/addrbook.json

# Add seeds and peers to the config.toml
PEERS="77d51624e042afadff5602286c76389522634c93@65.109.59.236:14656,453a74e2593dab9ef49abd6f7fe84a22cd37e303@24.199.118.15:14656,931da99598d6ecbd1e5f44551ad3a67b6e1d0fb4@62.171.146.0:14656,c2eb992910306ac43e6926dff467d73f1449a52b@65.109.56.247:14656,e838948adde1779e16f70ebd7f1b46b38710bb22@207.188.6.109:26666,113082f983df71333b97fda3adc337bf3363fbd9@65.108.123.126:14656"
SEEDS="2eaa272622d1ba6796100ab39f58c75d458b9dbc@34.142.181.82:26656,c28827cb96c14c905b127b92065a3fb4cd77d7f6@testnet-seeds.whispernode.com:25756"

sed -i -e "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" $HOME/.initia/config/config.toml
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/" $HOME/.initia/config/config.toml

# Change ports
sed -i \
    -e "s/\(proxy_app = \"tcp:\/\/\)\([^:]*\):\([0-9]*\).*/\1\2:$PROXY_APP_PORT\"/" \
    -e "s/\(laddr = \"tcp:\/\/\)\([^:]*\):\([0-9]*\).*/\1\2:$RPC_PORT\"/" \
    -e "s/\(pprof_laddr = \"\)\([^:]*\):\([0-9]*\).*/\1localhost:$PPROF_PORT\"/" \
    -e "/\[p2p\]/,/^\[/{s/\(laddr = \"tcp:\/\/\)\([^:]*\):\([0-9]*\).*/\1\2:$P2P_PORT\"/}" \
    -e "/\[p2p\]/,/^\[/{s/\(external_address = \"\)\([^:]*\):\([0-9]*\).*/\1${EXTERNAL_IP}:$P2P_PORT\"/; t; s/\(external_address = \"\).*/\1${EXTERNAL_IP}:$P2P_PORT\"/}" \
    $HOME/.initia/config/config.toml

sed -i \
  -e "/\[api\]/,/^\[/{s/\(address = \"tcp:\/\/\)\([^:]*\):\([0-9]*\)\(\".*\)/\1\2:$API_PORT\4/}" \
  -e "/\[grpc\]/,/^\[/{s/\(address = \"\)\([^:]*\):\([0-9]*\)\(\".*\)/\1\2:$GRPC_PORT\4/}" \
  -e "/\[grpc-web\]/,/^\[/{s/\(address = \"\)\([^:]*\):\([0-9]*\)\(\".*\)/\1\2:$GRPC_WEB_PORT\4/}" \
  $HOME/.initia/config/app.toml

# Configure pruning to save storage (Optional)
sed -i -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.15uinit,0.01uusdc\"/" $HOME/.initia/config/app.toml

# Set min gas price
sed -i -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.15uinit,0.01uusdc\"/" $HOME/.initia/config/app.toml

# Create a service file
sudo tee /etc/systemd/system/initiad.service > /dev/null <<EOF
[Unit]
Description=Initia Node
After=network.target

[Service]
User=root
Type=simple
ExecStart=/root/go/bin/initiad start --home /root/.initia
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Start node
sudo systemctl daemon-reload
sudo systemctl enable initiad
sudo systemctl restart initiad
#
if sudo systemctl is-active --quiet initiad && ! sudo systemctl is-failed initiad; then
    echo -e "\n Initiad service start successfully."
else
    echo -e "\n OH SHIT ERORRRRRRRRRRRRRRRR"
    echo " rune command to check error => sudo journalctl -u initiad -f -o cat"
    exit 1  
fi


echo "Waiting to sync block..."
while true; do
    #should be fail
    if [ "$(/root/go/bin/initiad status | jq -r .sync_info.catching_up)" == "false" ]; then
        break
    fi
    local_height=$(/root/go/bin/initiad status | jq -r .sync_info.latest_block_height)
    network_height=$(curl -s https://rpc-initia-testnet.trusted-point.com/status | jq -r .result.sync_info.latest_block_height)
    blocks_left=$((network_height - local_height))
    echo ""
    echo "Your node height: $local_height"
    echo "Network height: $network_height"
    echo " => Blocks left: $blocks_left <="
    sleep 30
done



echo "create-validator"
initiad tx mstaking create-validator \
  --amount=1000000uinit \
  --pubkey=$(initiad tendermint show-validator) \
  --moniker=$MONIKER \
  --chain-id=$CHAIN_ID \
  --commission-rate=0.05 \
  --commission-max-rate=0.10 \
  --commission-max-change-rate=0.01 \
  --from=$WALLET_NAME \
  --identity="" \
  --website="" \
  --details="on it" \
  --gas=2000000 --fees=300000uinit \
  -y



echo "Delegate tokens to your validator"
sleep 3
initiad tx mstaking delegate $(initiad keys show $WALLET_NAME --bech val -a)  10000000uinit --from $WALLET_NAME --gas=2000000 --fees=300000uinit -y


echo " DONE ALL "
