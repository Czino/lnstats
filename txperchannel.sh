payments=$(lncli listpayments | jq -r '.payments' | jq length)
channels=$(lncli listchannels | jq -r '[.channels[] | select(.initiator == true)]' | jq -r length)
txPerChannelOpening=$(expr $payments / $channels)

echo "You opened $channels channels and made $payments payments which results in $txPerChannelOpening transactions per on-chain transaction."
