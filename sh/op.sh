#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

# Validate an Ethereum address using cast.
validate_address() {
  local addr="$1"
  if ! cast --to-checksum "$addr" >/dev/null 2>&1; then
    echo "Invalid address: $addr"
    exit 1
  fi
}

# Prompt for a staker/proposer address and validate it.
ask_address() {
  local prompt="$1"
  local var="$2"
  while true; do
    read -r -p "$prompt" value
    if validate_address "$value" 2>/dev/null; then
      eval "$var=\"$value\""
      return
    fi
    echo "Invalid address, please try again."
  done
}

# Prompt for a human-readable amount and convert it to wei.
ask_amount() {
  local var="$1"
  local value
  while true; do
    read -r -p "Amount (human readable, e.g. 1000): " value
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      eval "$var=\"$value\""
      return
    fi
    echo "Invalid amount, please enter a number."
  done
}

# Prompt for target pools; empty input uses the defaults.
ask_pools() {
  local var="$1"
  local input
  read -r -p "Target pools (bytes32, comma/space separated; empty for defaults): " input
  if [ -z "$input" ]; then
    eval "$var=\"\""
  else
    # Normalize commas to spaces so build_pool_array receives separate args.
    local cleaned="${input//,/ }"
    eval "$var=\"$cleaned\""
  fi
}

# Prompt for the signer and export the relevant environment variables.
ask_signer() {
  echo ""
  echo "Select signer:"
  select method in "private-key" "ledger" "trezor" "mnemonic"; do
    case "$method" in
      private-key)
        read -s -r -p "Private key (0x...): " key
        echo ""
        if [[ ! "$key" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
          echo "Invalid private key"
          exit 1
        fi
        export PRIVATE_KEY="$key"
        break
        ;;
      ledger)
        export LEDGER=1
        break
        ;;
      trezor)
        export TREZOR=1
        break
        ;;
      mnemonic)
        local idx path
        read -r -p "Mnemonic index: " idx
        [[ "$idx" =~ ^[0-9]+$ ]] || { echo "Invalid index"; exit 1; }
        export MNEMONIC_INDEX="$idx"
        read -r -p "HD path (optional): " path
        [ -n "$path" ] && export HD_PATHS="$path"
        break
        ;;
      *)
        echo "Invalid choice"
        ;;
    esac
  done
}

# Ask whether to simulate or execute.
ask_mode() {
  local mode
  read -r -p "Run mode — (s)imulate or (e)xecute? " mode
  if [ "$mode" = "e" ] || [ "$mode" = "E" ]; then
    unset DRY_RUN 2>/dev/null || true
  else
    export DRY_RUN=1
  fi
}

# Confirm before executing.
confirm() {
  if [ -z "${DRY_RUN:-}" ]; then
    local ok
    read -r -p "This will broadcast to the network. Continue? (y/N) " ok
    if [ "$ok" != "y" ] && [ "$ok" != "Y" ]; then
      echo "Aborted."
      exit 1
    fi
  fi
}

# Run a shell operation script, forwarding the chosen signer env vars.
run_op() {
  local script="$1"
  shift
  echo ""
  echo "▶ Running: $script $*"
  if [ -n "${PRIVATE_KEY:-}" ]; then
    echo "  signer: private-key"
  elif [ -n "${LEDGER:-}" ]; then
    echo "  signer: ledger"
  elif [ -n "${TREZOR:-}" ]; then
    echo "  signer: trezor"
  elif [ -n "${MNEMONIC_INDEX:-}" ]; then
    echo "  signer: mnemonic (index $MNEMONIC_INDEX)"
  fi
  if [ -n "${DRY_RUN:-}" ]; then
    echo "  mode: simulate (DRY_RUN=1)"
  else
    echo "  mode: execute (broadcast)"
  fi
  "$(dirname "$0")/$script" "$@"
}

echo "Select operation:"
select op in \
  "stake-delegate" \
  "delegate-equal" \
  "redelegate" \
  "wrap" \
  "treasury" \
  "quit"; do

  case "$op" in
    stake-delegate)
      ask_address "Staker address: " staker
      ask_amount amount
      ask_pools pools
      ask_signer
      ask_mode
      confirm
      if [ -z "$pools" ]; then
        run_op stake-and-delegate.sh "$staker" "$amount"
      else
        run_op stake-and-delegate.sh "$staker" "$amount" $pools
      fi
      break
      ;;

    delegate-equal)
      ask_address "Staker address: " staker
      ask_amount amount
      ask_pools pools
      ask_signer
      ask_mode
      confirm
      if [ -z "$pools" ]; then
        run_op delegate-equal.sh "$staker" "$amount"
      else
        run_op delegate-equal.sh "$staker" "$amount" $pools
      fi
      break
      ;;

    redelegate)
      echo "Select redelegate mode:"
      select mode in "undelegate-all" "redelegate-all" "redelegate-amount"; do
        [ -n "$mode" ] && break
      done
      ask_address "Staker address: " staker
      local target_amount=0
      if [ "$mode" = "redelegate-amount" ]; then
        ask_amount target_amount
      fi
      ask_pools pools
      ask_signer
      ask_mode
      confirm
      if [ -z "$pools" ]; then
        run_op redelegate.sh "$mode" "$staker" "$target_amount"
      else
        run_op redelegate.sh "$mode" "$staker" "$target_amount" $pools
      fi
      break
      ;;

    wrap)
      echo "Select wrap mode:"
      select mode in "liquid" "full" "exclude-pools" "unstake"; do
        [ -n "$mode" ] && break
      done
      ask_address "Staker address: " staker
      ask_address "Delegatee address: " delegatee
      ask_amount amount
      local exclude=""
      if [ "$mode" = "exclude-pools" ]; then
        ask_pools exclude
      fi
      ask_signer
      ask_mode
      confirm
      if [ "$mode" = "exclude-pools" ]; then
        if [ -z "$exclude" ]; then
          run_op wrap-governance.sh "$mode" "$staker" "$delegatee" "$amount"
        else
          run_op wrap-governance.sh "$mode" "$staker" "$delegatee" "$amount" $exclude
        fi
      else
        run_op wrap-governance.sh "$mode" "$staker" "$delegatee" "$amount"
      fi
      break
      ;;

    treasury)
      echo "Select treasury mode:"
      select mode in "propose" "execute"; do
        [ -n "$mode" ] && break
      done
      ask_address "Proposer address: " proposer
      ask_signer
      ask_mode
      confirm
      if [ "$mode" = "execute" ]; then
        local proposal_id
        read -r -p "Proposal ID: " proposal_id
        run_op treasury.sh "$mode" "$proposer" "$proposal_id"
      else
        ask_pools pools
        if [ -z "$pools" ]; then
          run_op treasury.sh "$mode" "$proposer"
        else
          run_op treasury.sh "$mode" "$proposer" $pools
        fi
      fi
      break
      ;;

    quit)
      echo "Goodbye."
      exit 0
      ;;

    *)
      echo "Invalid choice"
      ;;
  esac
done
