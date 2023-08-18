import {
  LCDClient,
  Wallet,
  MnemonicKey,
  MsgPublish,
  MsgExecute,
  AccAddress,
  BCS
} from '@initia/initia.js';
import { readFileSync } from 'fs';

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

  const moneyMarket = readFileSync(
    'contracts/build/money-market/bytecode_modules/MoneyMarket.mv'
  ).toString('base64');
  const coinType = readFileSync(
    'contracts/build/money-market/bytecode_modules/CoinType.mv'
  ).toString('base64');
  const bcs = BCS.getInstance();

  const msgs = [
    new MsgPublish(
      wallet.key.accAddress,
      [moneyMarket, coinType],
      MsgPublish.Policy.COMPATIBLE
    ),
    new MsgExecute(
      wallet.key.accAddress,
      wallet.key.accAddress,
      'CoinType',
      'initialize',
      [`${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinA`],
      [
        bcs.serialize(BCS.STRING, 'loan coin'),
        bcs.serialize(BCS.STRING, 'LOAN'),
        bcs.serialize(BCS.U8, 6)
      ]
    ),
    new MsgExecute(
      wallet.key.accAddress,
      wallet.key.accAddress,
      'CoinType',
      'initialize',
      [`${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinB`],
      [
        bcs.serialize(BCS.STRING, 'collateral coin'),
        bcs.serialize(BCS.STRING, 'COL'),
        bcs.serialize(BCS.U8, 6)
      ]
    ),
    new MsgExecute(
      wallet.key.accAddress,
      '0x1',
      'coin',
      'register',
      [`${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinA`],
      []
    ),
    new MsgExecute(
      wallet.key.accAddress,
      '0x1',
      'coin',
      'register',
      [`${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinB`],
      []
    ),
    new MsgExecute(
      wallet.key.accAddress,
      wallet.key.accAddress,
      'CoinType',
      'mint',
      [`${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinA`],
      [
        bcs.serialize(BCS.ADDRESS, wallet.key.accAddress),
        bcs.serialize(BCS.U64, 1_000_000_000_000)
      ]
    ),
    new MsgExecute(
      wallet.key.accAddress,
      wallet.key.accAddress,
      'CoinType',
      'mint',
      [`${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinB`],
      [
        bcs.serialize(BCS.ADDRESS, wallet.key.accAddress),
        bcs.serialize(BCS.U64, 1_000_000_000_000)
      ]
    ),
    new MsgExecute(
      wallet.key.accAddress,
      wallet.key.accAddress,
      'MoneyMarket',
      'create_money_pool',
      [`${AccAddress.toHex(wallet.key.accAddress)}::CoinType::CoinA`],
      [
        bcs.serialize(BCS.STRING, '0.05'), // annual inflation rate : 5   %
        bcs.serialize(BCS.STRING, '1.5'), //  min LTV               : 150 %
        bcs.serialize(BCS.STRING, '0.1') //   discount rate         : 10  %
      ]
    )
  ];

  const tx = await wallet.createAndSignTx({
    msgs
  });

  const res = await lcdClient.tx.broadcast(tx);
  console.info(`initialize tx: ${res.txhash}`);
}

main().then(console.info).catch(console.error);
