import { MnemonicKey } from '@initia/initia.js';

const mnemonicKey = new MnemonicKey();
console.info(`Created Wallet Info:
    address: "${mnemonicKey.accAddress}"
    mnemonic: "${mnemonicKey.mnemonic}"
`);
