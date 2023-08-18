import {
  LCDClient,
  Wallet,
  MnemonicKey,
  MsgExecute,
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
  const msgs = [
    new MsgExecute(
      wallet.key.accAddress,
      wallet.key.accAddress,
      'MoneyMarket',
      'withdraw_script',
      [`${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinA`],
      [
        bcs.serialize(BCS.ADDRESS, wallet.key.accAddress),
        bcs.serialize(BCS.U64, 1_000_000_000)
      ]
    )
  ];

  const tx = await wallet.createAndSignTx({
    msgs
  });

  const res = await lcdClient.tx.broadcast(tx);
  console.info(`deposit tx: ${res.txhash}`);
}

main().then(console.info).catch(console.error);
