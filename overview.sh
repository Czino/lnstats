NC='\033[0m' # No Color
RED='\033[0m'
GREEN='\033[0m'
ORANGE='\033[0m'

stop=false

_setArgs(){
  while [ "$1" != "" ]; do
    case $1 in
      "-h" | "--help")
        echo "options:"
        echo "-h, --help         show brief help"
        echo "-c, --color    (optional) add colors to output"
        stop=true
        ;;
      "-c" | "--color")
        shift
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        ORANGE='\033[0;33m'
        ;;
    esac
    shift
  done
}

_setArgs $*

if "$stop"; then
  return
fi

MINIMUM_TX_SIZE=109 # in virtual bytes, assuming no change output
MINIMUM_TX_SIZE_CHANNEL_OPENING=121 # in virtual bytes, assuming no change output
KILOBYTE=1024
MEGABYTE=$(expr 1024 \* 1024)
ONEMILLION=1000000
ONETHOUSAND=1000

payments=$(lncli listpayments | jq -r '[.payments[] | select(.status == "SUCCEEDED")]')
paymentAmount=$(echo "$payments" | jq -r length)
totalFeesPaid=$(echo "$payments" | jq -r '. | map(.fee_sat | tonumber) | add')
channels=$(lncli listchannels | jq -r '[.channels[] | select(.initiator == true)]' | jq -r length)
closedChannels=$(lncli closedchannels | jq -r '[.channels[] | select(.open_initiator == "INITIATOR_LOCAL")]' | jq -r length)
let onchainTx="$channels"+"$closedChannels"*2
let txPerOnchainTx="$paymentAmount"/"$onchainTx"
let minimumSpaceUsed="$MINIMUM_TX_SIZE_CHANNEL_OPENING"*"$onchainTx"
let minimumSpaceSaved="$MINIMUM_TX_SIZE"*"$paymentAmount"-"$minimumSpaceUsed"
let minimumFeesSaved="$paymentAmount"*"$MINIMUM_TX_SIZE"-"$minimumSpaceUsed"

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

if [ "$totalFeesPaid" -ge "$ONEMILLION" ]; then
    totalFeesPaid=$(($totalFeesPaid / $ONEMILLION))
    totalFeesPaid=$(echo "${totalFeesPaid}M sats")
elif [ "$totalFeesPaid" -ge "$ONETHOUSAND" ]; then
    totalFeesPaid=$(($totalFeesPaid / $ONETHOUSAND))
    totalFeesPaid=$(echo "${totalFeesPaid}k sats")
else
    totalFeesPaid=$(echo "$totalFeesPaid sats")
fi
if [ "$minimumFeesSaved" -ge "$ONEMILLION" ]; then
    minimumFeesSaved=$(($minimumFeesSaved / $ONEMILLION))
    minimumFeesSaved=$(echo "${minimumFeesSaved}M sats")
elif [ "$minimumFeesSaved" -ge "$ONETHOUSAND" ]; then
    minimumFeesSaved=$(($minimumFeesSaved / $ONETHOUSAND))
    minimumFeesSaved=$(echo "${minimumFeesSaved}k sats")
else
    minimumFeesSaved=$(echo "$minimumFeesSaved sats")
fi

echo -e "You opened ${ORANGE}$channels channels${NC}, closed ${RED}$closedChannels channels${NC} and made ${ORANGE}$paymentAmount lightning payments${NC} which results in ${ORANGE}$txPerOnchainTx transactions${NC} per on-chain transaction."
echo -e "You used at least ${RED}$minimumSpaceUsed${NC} block space but saved at least ${GREEN}$minimumSpaceSaved${NC}."
echo -e "You paid ${RED}$totalFeesPaid${NC} in lightning fees but saved at least ${GREEN}$minimumFeesSaved${NC} by using lightning."
