import {
  LCDClient,
  Wallet,
  MnemonicKey,
  AccAddress,
  BCS
} from '@initia/initia.js';

async function main() {
  const lcdClient = new LCDClient('http://127.0.0.1:1317');

  // go to https://faucet.initia.tech to get the token
  const wallet = new Wallet(
    lcdClient,
    new MnemonicKey({
      mnemonic:
        // init15zv8lgvvw9h00kta9nlhvwdts8khql9yvzrf5e
        // 0xA0987FA18C716EF7D97D2CFF7639AB81ED707CA4
        'twice science awkward pencil person insect input filter neutral hill sunset smart post swear toe dinosaur catch west swim pulse pretty poet forum teach'
    })
  );
  const bcs = BCS.getInstance();
  const res = await lcdClient.move.viewFunction(
    wallet.key.accAddress,
    'MoneyMarket',
    'get_borrow_position',
    [
      `${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinB`,
      `${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinA`
    ],
    [
      bcs.serialize(BCS.ADDRESS, wallet.key.accAddress),
      bcs.serialize(BCS.ADDRESS, wallet.key.accAddress)
    ]
  );

  console.info(`deposit:`, res);
}

main().then(console.info).catch(console.error);
