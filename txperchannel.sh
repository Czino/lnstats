MINIMUM_TX_SIZE=109 # in virtual bytes, assuming no change output
MINIMUM_TX_SIZE_CHANNEL_OPENING=121 # in virtual bytes, assuming no change output
KILOBYTE=1024
MEGABYTE=$(expr 1024 \* 1024)

payments=$(lncli listpayments | jq -r '.payments' | jq length)
channels=$(lncli listchannels | jq -r '[.channels[] | select(.initiator == true)]' | jq -r length)
closedChannels=$(lncli closedchannels | jq -r '[.channels[] | select(.open_initiator == "INITIATOR_LOCAL")]' | jq -r length)
let onchainTx="$channels"+"$closedChannels"
let txPerOnchainTx="$payments"/"$onchainTx"
let minimumSpaceUsed="$MINIMUM_TX_SIZE_CHANNEL_OPENING"*"$onchainTx"
let minimumSpaceSaved="$MINIMUM_TX_SIZE"*"$payments-$minimumSpaceUsed"

if [ "$minimumSpaceUsed" -ge "$MEGABYTE" ]; then
    minimumSpaceUsed=$(($minimumSpaceUsed / $MEGABYTE))
    minimumSpaceUsed=$(echo "$minimumSpaceUsed vMB")
elif [ "$minimumSpaceUsed" -ge "$KILOBYTE" ]; then
    minimumSpaceUsed=$(($minimumSpaceUsed / $KILOBYTE))
    minimumSpaceUsed=$(echo "$minimumSpaceUsed vKB")
else
    minimumSpaceUsed=$(echo "$minimumSpaceUsed vB")
fi
if [ "$minimumSpaceSaved" -ge "$MEGABYTE" ]; then
    minimumSpaceSaved=$(($minimumSpaceSaved / $MEGABYTE))
    minimumSpaceSaved=$(echo "$minimumSpaceSaved vMB")
elif [ "$minimumSpaceSaved" -ge "$KILOBYTE" ]; then
    minimumSpaceSaved=$(($minimumSpaceSaved / $KILOBYTE))
    minimumSpaceSaved=$(echo "$minimumSpaceSaved vKB")
else
    minimumSpaceSaved=$(echo "$minimumSpaceSaved vB")
fi
echo "You opened $channels channels, closed $closedChannels channels and made $payments payments which results in $txPerOnchainTx transactions per online transaction"
echo "You used at least $minimumSpaceUsed blockspace but saved at least $minimumSpaceSaved"
