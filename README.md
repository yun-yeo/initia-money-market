# Optimism Bridge Executor

## How to use

### Install package

```sh
npm install @initia/op-bridge-executor
```

### Create distribution list

`txs.json`

```json
{
  "txs": [
    {
      "sequence": 100,
      "sender": "0x996",
      "receiver": "0x995",
      "amount": 1000000,
      "coin_type": "0x1::native_uinit::Coin"
    },
    {
      "sequence": 100,
      "sender": "0x994",
      "receiver": "0x996",
      "amount": 2000000,
      "coin_type": "0x1::native_uinit::Coin"
    },
    {
      "sequence": 100,
      "sender": "0x995",
      "receiver": "0x996",
      "amount": 3000000,
      "coin_type": "0x1::native_uinit::Coin"
    },
    ...
  ]
}
```

### Get proof with user input

```javascript
import { WithdrawStorage } from "@initia/op-bridge-executor";
import { txs } from "../txs.json";

const storage = new WithdrawStorage(txs);
const proof = storage.getMerkleProof(txs[0]);

console.log("Merkle Root", storage.getMerkleRoot());
console.log("Merkle Proof", proof);
console.log("Target Acc", accounts[0]);
console.log("Verified", storage.verify(proof, accounts[0]));
```
