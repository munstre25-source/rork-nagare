# Kiku recordings: channel inventory and filters

Reviewed all three supplied recordings, the full Explore scroll, and 23 channel-label contact sheets. The JSON/CSV retain 1343 normalized label groups from 1,557 raw OCR readings; these are **not** 1343 verified unique YouTube channels. 39 distinct channel IDs match the earlier verified screenshot inventory. Truncated names, aliases and uncertain glyphs stay explicit. No Gemini or paid inference was used.

Full machine-readable inventory: [JSON](kiku-recordings-20261105.json), [CSV](kiku-recordings-20261105.csv). Source evidence is the original recording filename plus time in seconds; crop coordinates and OCR variants are in JSON.

## Observed discovery controls

The Explore list shows **5060 clips found**, transcript previews, titles, creator footers, per-clip JLPT badges and Watched pills. Its search placeholder supports English, Japanese and romaji words. Selected category chips can be removed individually. The filter modal has Reset and Apply controls and supports multiple selected chips.

**difficulty** (5): N5, N4, N3, N2, N1.

**grammar** (9): Past tense, Negative, Polite (ます), Progressive (〜ている), Passive, Causative, Te-form (〜て), Conditional, Want to (〜たい).

**topic** (27): Animals, Beauty, Business, Comedy, Cooking, Exercise, Family, Fashion, Food, Gaming, Health, History, Household, Japanese Culture, Morning Routine, Music, Nature, Outdoors, Relationships, Romance, School, Shopping, Sports, Study, Technology, Travel, Work.

**sourceType** (12): Anime, Cartoon, Drama, Movie, Music, News, Vlog, Podcast, Interview, Lecture, Variety, Lesson.

Evidence: `191043` recording at 5 s (Difficulty/Grammar) and 10 s (Topic/Source Type). The 199-second playback recording separately shows profile Japanese Level N5–N1; changing a profile level does not establish that every clip shares that level.

## Learning controls

Observed Highlight Spoken Word, Manual Saving, Text Size, Dictionary Popup Size, Focus Mode, Show Furigana, Show Romaji, Show Translation and Show Word Spacing. The dictionary links conjugated forms to a base expression (for example お腹が空いたら → お腹が空く), and exposes senses/examples/audio. Creator headers visible in this recording include グルメバイトちゃん (15 s), とも先生【数学勉強法】 (60 s) and ハシダ (75 s).

## Applying the pattern to Jojo

Proposed implementation, inferred from the visible behavior: keep source type, topic tags, grammar tags and estimated JLPT difficulty as separate facets. Derive grammar from offline base-form/conjugation analysis; index Japanese, kana, romaji and English for search. Estimate each clip’s difficulty from vocabulary, grammar, speech rate and dictionary coverage, with an unrated state when evidence is insufficient. Keep watched state per user and profile proficiency separate from clip difficulty. The recordings do not reveal Kiku’s classifier or exact AND/OR rules; those cannot be claimed as observed. This audit does not deploy a new filter UI.

## Extracted labels

A name without a channel ID remains an identity-resolution candidate. An ellipsis is preserved rather than expanded from guesswork. Repeated visible aliases can still refer to one channel.

| Visible label | Identity / limitation | First evidence (seconds) |
| --- | --- | --- |
| あさぎーにょ | label only | 190933_Kiku.mp4 · 81.048 |
| TOHO animation | label only | 190933_Kiku.mp4 · 53.786 |
| ハウスダスト | label only | 190933_Kiku.mp4 · 44.538 |
| のすけぼっち飯 | UCW1m4ZOBYZ8mWXCPX-5EMqg | 190933_Kiku.mp4 · 113.916 |
| HikakinClipTV | label only | 190933_Kiku.mp4 · 170.908 |
| あいりDX看護専門学校 | label only | 190933_Kiku.mp4 · 64.083 |
| 笑ンク | label only | 190933_Kiku.mp4 · 10.061 |
| らてあーと | label only | 190933_Kiku.mp4 · 286.949 |
| The Sports Times | label only | 190933_Kiku.mp4 · 34.259 |
| サネマリー公式 | label only | 190933_Kiku.mp4 · 215.439 |
| 1分日報 | label only | 190933_Kiku.mp4 · 108.776 |
| 西田くん | label only | 190933_Kiku.mp4 · 125.246 |
| 神編集 | label only | 190933_Kiku.mp4 · 43.507 |
| kikuhito | label only | 190933_Kiku.mp4 · 303.835 |
| ジェシーズトレVLOG | label only | 190933_Kiku.mp4 · 30.15 |
| 空寝る筋子（カンゴャンセウ』 | label only; uncertain glyphs | 190933_Kiku.mp4 · 351.376 |
| タイチ -Flexible Body | label only | 190933_Kiku.mp4 · 203.12 |
| リズミカルパパ | label only | 190933_Kiku.mp4 · 170.908 |
| Kailog | label only | 190933_Kiku.mp4 · 170.908 |
| 堀大輔の日常 | label only | 190933_Kiku.mp4 · 78.471 |
| たろたん | UCAmX4-xOCziCUAXPBu39NEQ | 190933_Kiku.mp4 · 45.569 |
| トリビアの沼 | label only | 190933_Kiku.mp4 · 3.377 |
| みさき | label only | 190933_Kiku.mp4 · 123.135 |
| バズ神殿 | label only | 190933_Kiku.mp4 · 20.886 |
| チョコチップ | label only | 190933_Kiku.mp4 · 214.408 |
| Next Scene | label only | 190933_Kiku.mp4 · 145.217 |
| ぱぼちゃん | label only | 190933_Kiku.mp4 · 72.815 |
| 葉月ひまり | label only | 190933_Kiku.mp4 · 14.17 |
| 1分スポーツ | label only | 190933_Kiku.mp4 · 0.0 |
| もふもふ事件簿 | UCDjXp2mwq3fvfRIBlvHuOAw | 190933_Kiku.mp4 · 10.576 |
| ひろすき（切り抜き | label only | 190933_Kiku.mp4 · 42.991 |
| 712ダリルのオススメしまくるチャンネル | label only; uncertain glyphs | 190933_Kiku.mp4 · 74.346 |
| TentenHanten | label only | 190933_Kiku.mp4 · 92.89 |
| もとき | label only | 190933_Kiku.mp4 · 37.852 |
| 熱血シネマ部 | label only | 190933_Kiku.mp4 · 4.922 |
| 動画、はじめてみました【テレビ朝日公式】 | label only | 190933_Kiku.mp4 · 178.581 |
| Tokyo Playlist | label only | 190933_Kiku.mp4 · 99.061 |
| サッカーワールド | label only | 190933_Kiku.mp4 · 491.119 |
| 1分大学 | label only | 190933_Kiku.mp4 · 33.244 |
| おかじゅん | label only | 190933_Kiku.mp4 · 15.232 |
| Suit Travel | label only | 190933_Kiku.mp4 · 273.239 |
| 西宮正悟 | label only | 190933_Kiku.mp4 · 307.431 |
| 片倉岳人/ダイエットの知恵袋 | label only | 190933_Kiku.mp4 · 170.393 |
| だいちマン | label only | 190933_Kiku.mp4 · 127.277 |
| テセサクch | label only | 190933_Kiku.mp4 · 34.775 |
| ゆり>2人目妊娠中の助産師ママ | label only | 190933_Kiku.mp4 · 27.056 |
| まゆみん〔ソロキャンプとハイエース車中. | label only | 190933_Kiku.mp4 · 35.791 |
| ブレイクスルー佐々木 | label only | 190933_Kiku.mp4 · 24.994 |
| Toptuan | label only | 190933_Kiku.mp4 · 85.688 |
| やんばる学園の放課後 | label only | 190933_Kiku.mp4 · 344.277 |
| アニメ絵創作室 | UC0-qJgMEVVI4dKJd20DsCkA | 190933_Kiku.mp4 · 30.15 |
| 深夜食堂 | label only | 190933_Kiku.mp4 · 251.594 |
| やみちゃんねる。 | label only | 190933_Kiku.mp4 · 258.948 |
| 古森もぐ | label only | 190933_Kiku.mp4 · 0.0 |
| バイトな日常 | label only | 190933_Kiku.mp4 · 72.3 |
| 石川典行チャンネル | label only | 190933_Kiku.mp4 · 252.61 |
| ごくーチャンネル | label only | 190933_Kiku.mp4 · 360.522 |
| ニヤリハット | label only | 190933_Kiku.mp4 · 108.261 |
| SAGIRIX | label only | 190933_Kiku.mp4 · 178.581 |
| ANIMAT! | label only | 190933_Kiku.mp4 · 369.137 |
| manaのアイデア料理 | UCaMw5qcJdms7Ys-axWihFSQ | 190933_Kiku.mp4 · 54.817 |
| おませちゃんブラザーズ | label only | 190933_Kiku.mp4 · 164.219 |
| ひすいこたろうの名言セラピー | label only | 190933_Kiku.mp4 · 271.207 |
| シバヨガチャンネル | label only | 190933_Kiku.mp4 · 251.094 |
| Yukari's Easy Japanese Home Cooking Re... | partial name | 190933_Kiku.mp4 · 234.515 |
| 生活習慣改革ラボ | label only | 190933_Kiku.mp4 · 12.123 |
| くぼたび1年300日くらい旅する夫婦 | label only | 190933_Kiku.mp4 · 34.259 |
| 僕のヒーローアカデミア名シーンランキン.. | partial name | 190933_Kiku.mp4 · 133.401 |
| ごをくんな動画ch | label only | 190933_Kiku.mp4 · 10.576 |
| JAPAN BASEBALL Ch. | label only | 190933_Kiku.mp4 · 208.747 |
| バーキン君 | label only | 190933_Kiku.mp4 · 65.114 |
| ハコジム（フィットネス情報] | label only | 190933_Kiku.mp4 · 212.891 |
| 日本に筋肉を | label only | 190933_Kiku.mp4 · 273.239 |
| 今日も寝ない | label only | 190933_Kiku.mp4 · 108.776 |
| まいぱん | label only | 190933_Kiku.mp4 · 113.916 |
| うわさの探偵たち | label only | 190933_Kiku.mp4 · 27.056 |
| Thuong Khánh | label only | 190933_Kiku.mp4 · 18.325 |
| オリンピックの雑学 | label only | 190933_Kiku.mp4 · 220.147 |
| 混血のカレコレ | label only | 190933_Kiku.mp4 · 243.208 |
| わせだや | label only | 190933_Kiku.mp4 · 431.006 |
| ぶいすぽ好きの小林さん | label only | 190933_Kiku.mp4 · 217.1 |
| 野球選手紹介CH | label only | 190933_Kiku.mp4 · 72.815 |
| タカサックゴルフチャンネル | label only | 190933_Kiku.mp4 · 80.533 |
| ひみつ基地。 | UC4b2j0oY5iop4cqREcBGs3A | 190933_Kiku.mp4 · 99.575 |
| 小物ロマン | UCXWP0u_nhbylEwRtFzmAyrA | 190933_Kiku.mp4 · 208.747 |
| うんうん・ogaっち | label only | 190933_Kiku.mp4 · 99.575 |
| ポテトのタカタク | label only | 190933_Kiku.mp4 · 123.135 |
| ムックの宝庫 | label only | 190933_Kiku.mp4 · 44.538 |
| タソガレドキ | label only | 190933_Kiku.mp4 · 147.263 |
| ニナク星 | label only | 190933_Kiku.mp4 · 66.66 |
| 動物ふしぎ発見 | label only | 190933_Kiku.mp4 · 210.844 |
| ゆう先生の美容整体塾（京都の整体院悠 | label only | 190933_Kiku.mp4 · 113.4 |
| NewsPicks/ニューズピックス | label only | 190933_Kiku.mp4 · 76.924 |
| 鈴木メトロchannel | label only | 190933_Kiku.mp4 · 5.438 |
| 【公式】朝倉千恵子チャンネル | label only | 190933_Kiku.mp4 · 122.619 |
| 気晴らし部（支部] | label only; low OCR confidence | 190933_Kiku.mp4 · 41.96 |
| 東京ウーバーズ | label only | 190933_Kiku.mp4 · 151.373 |
| アウトドアがツマミ | label only | 190933_Kiku.mp4 · 17.294 |
| マイケル社長 | label only | 190933_Kiku.mp4 · 11.607 |
| バナナショート | label only | 190933_Kiku.mp4 · 478.302 |
| よんう | label only | 190933_Kiku.mp4 · 146.747 |
| ともき | UCZ0obDWBeumW3Tk3jDcjxwg | 190933_Kiku.mp4 · 44.538 |
| 1分動画 | label only | 190933_Kiku.mp4 · 125.761 |
| Nanaomi | label only | 190933_Kiku.mp4 · 153.984 |
| コトコト | label only | 190933_Kiku.mp4 · 237.095 |
| はたのあいか声真似チャンネル | label only | 190933_Kiku.mp4 · 384.754 |
| ときめき図鑑 | label only | 190933_Kiku.mp4 · 51.756 |
| Troy | label only | 190933_Kiku.mp4 · 54.302 |
| 部活と恋 | label only | 190933_Kiku.mp4 · 206.2 |
| まじめくん | label only | 190933_Kiku.mp4 · 42.476 |
| キナコジジイ | label only | 190933_Kiku.mp4 · 70.238 |
| えだまめロン | label only | 190933_Kiku.mp4 · 42.476 |
| あかちゃす丸裸 | UCf68P7dWjIOLdKY24IyU1Wg | 190933_Kiku.mp4 · 356.973 |
| 本日も絶体絶命。 | label only | 190933_Kiku.mp4 · 28.087 |
| 知りたいニッポン | label only | 190933_Kiku.mp4 · 167.813 |
| i li ai | label only | 190933_Kiku.mp4 · 37.852 |
| べいみいカップル | label only | 190933_Kiku.mp4 · 148.81 |
| なかむ手取り18万の簡単節約レシピ | label only | 190933_Kiku.mp4 · 86.719 |
| 世界ビックリ発見 | label only | 190933_Kiku.mp4 · 220.663 |
| Cemister | label only | 190933_Kiku.mp4 · 611.414 |
| 毎日どうぶつ爆笑 | label only | 190933_Kiku.mp4 · 271.207 |
| Daiki MusihiokaJapanese Insect YouTuber. | label only | 190933_Kiku.mp4 · 55.833 |
| ブルーシー(Blue Sea] | label only | 190933_Kiku.mp4 · 79.503 |
| 元運動音痴が教える体の改善術 パーソナ.. | partial name | 190933_Kiku.mp4 · 60.505 |
| Shoto Golf上金子奨投 | label only | 190933_Kiku.mp4 · 212.891 |
| ミケネコ〔声真似YOUTuber] | label only; low OCR confidence | 190933_Kiku.mp4 · 97.514 |
| RKPhotO_9チャンネル | label only; low OCR confidence | 190933_Kiku.mp4 · 316.69 |
| スポナビゴルフ | label only | 190933_Kiku.mp4 · 400.15 |
| 一瞬だけ | label only | 190933_Kiku.mp4 · 50.209 |
| 東京チル・ドレン | label only | 190933_Kiku.mp4 · 254.691 |
| サッカーマン | label only | 190933_Kiku.mp4 · 226.791 |
| あも。 | label only | 190933_Kiku.mp4 · 121.603 |
| そば湯 | label only | 190933_Kiku.mp4 · 85.688 |
| RISE | label only | 190933_Kiku.mp4 · 354.424 |
| 1分オーブン | label only | 190933_Kiku.mp4 · 162.478 |
| キュリエーション学院 | label only | 190933_Kiku.mp4 · 334.08 |
| baseball. worldclub | label only | 190933_Kiku.mp4 · 145.217 |
| ももとゆなの日常 | label only | 190933_Kiku.mp4 · 214.923 |
| わたくわチャンネル | label only | 190933_Kiku.mp4 · 21.386 |
| まさ/高倉正善 | label only | 190933_Kiku.mp4 · 81.564 |
| もふもふ派 | label only | 190933_Kiku.mp4 · 240.677 |
| nanakoななこ | label only | 190933_Kiku.mp4 · 25.511 |
| 麺ドラ | label only | 190933_Kiku.mp4 · 252.11 |
| ハシダ | label only | 190933_Kiku.mp4 · 198.429 |
| 全力回避フラグちゃん!/Flag Chan! | label only | 190933_Kiku.mp4 · 55.333 |
| Sake and Traveling Sakurako Chan🍺 | label only | 190933_Kiku.mp4 · 109.807 |
| 直也テック | label only | 190933_Kiku.mp4 · 86.204 |
| 岡野タケシ弁護士（アトム法律税務グルー. | label only | 190933_Kiku.mp4 · 47.631 |
| プロテニス解説チャンネル【プテカイ】 | label only | 190933_Kiku.mp4 · 91.343 |
| えんどれす（Endless] | label only | 190933_Kiku.mp4 · 67.676 |
| ふわくん /Fuwakun | label only | 190933_Kiku.mp4 · 153.468 |
| Ly hái | label only; low OCR confidence | 190933_Kiku.mp4 · 611.414 |
| シャトルの唱き | label only; low OCR confidence | 190933_Kiku.mp4 · 13.669 |
| (キナリムービー) | label only; low OCR confidence | 190933_Kiku.mp4 · 77.955 |
| Baseball in the Morning | label only | 190933_Kiku.mp4 · 27.056 |
| 北の打ち師達 | label only | 190933_Kiku.mp4 · 138.011 |
| 30秒教室 | label only | 190933_Kiku.mp4 · 124.73 |
| ななえる | label only | 190933_Kiku.mp4 · 153.984 |
| Ricky | label only | 190933_Kiku.mp4 · 202.088 |
| Azami Couple | label only | 190933_Kiku.mp4 · 58.443 |
| おのっち | label only | 190933_Kiku.mp4 · 184.741 |
| とみビデオ | label only | 190933_Kiku.mp4 · 250.062 |
| ゲーミングPCチャンネル | label only | 190933_Kiku.mp4 · 219.631 |
| ヘビさんのアウトドア日誌 | UCJeid4dNjpbM7ZZ6i9Z6wBA | 190933_Kiku.mp4 · 53.786 |
| どこぬし | label only | 190933_Kiku.mp4 · 21.386 |
| OGATORE | label only | 190933_Kiku.mp4 · 178.581 |
| かず先生の若返りセルフケア塾 | label only | 190933_Kiku.mp4 · 27.056 |
| Jinei_Golf | label only | 190933_Kiku.mp4 · 92.89 |
| 読書兄弟 | label only | 190933_Kiku.mp4 · 64.598 |
| 海外バズり紹介 | label only | 190933_Kiku.mp4 · 78.987 |
| むちゅう雑学 | label only | 190933_Kiku.mp4 · 58.959 |
| 名言の桃太郎 | label only | 190933_Kiku.mp4 · 384.239 |
| Zoe Recap | label only | 190933_Kiku.mp4 · 126.776 |
| ジャムおにいのパン教室 | label only | 190933_Kiku.mp4 · 56.895 |
| 泉ノ波あみの「あみです、どうも」 | label only | 190933_Kiku.mp4 · 101.622 |
| ibukitoyohe | label only | 190933_Kiku.mp4 · 102.653 |
| アイルトンモカ | label only | 190933_Kiku.mp4 · 286.449 |
| お気に入りショート | label only | 190933_Kiku.mp4 · 468.601 |
| チェリー東大/あきぴで | label only | 190933_Kiku.mp4 · 159.416 |
| SenseiBP | label only | 190933_Kiku.mp4 · 255.723 |
| タクマのコント。 | label only | 190933_Kiku.mp4 · 59.989 |
| これエエやん | label only | 190933_Kiku.mp4 · 74.346 |
| ゆずみつといっしよ | label only | 190933_Kiku.mp4 · 247.401 |
| MEME STORY | label only | 190933_Kiku.mp4 · 405.733 |
| Zuki vlog | label only | 190933_Kiku.mp4 · 265.062 |
| NeonNihon | label only | 190933_Kiku.mp4 · 491.119 |
| ピヨ先生の生物の本質・疑問（生物雑学 | label only | 190933_Kiku.mp4 · 683.492 |
| ぼっちの冒険 | label only | 190933_Kiku.mp4 · 112.37 |
| YASUKOの神意識チャンネル | label only | 190933_Kiku.mp4 · 65.114 |
| 名港モーターズ＠ウマル | label only | 190933_Kiku.mp4 · 143.169 |
| GOLFFREAKS(ゴルフフリークス) | label only | 190933_Kiku.mp4 · 324.787 |
| 御子神琴音/ MikogamiKotoneにじさん.. | partial name | 190933_Kiku.mp4 · 82.596 |
| レジスタンス | label only | 190933_Kiku.mp4 · 298.786 |
| VOLIXチャンネル | label only | 190933_Kiku.mp4 · 133.401 |
| 山澤礼明（筋肉チャンネル] | label only | 190933_Kiku.mp4 · 138.011 |
| いぶよヘスカッシユ | label only; low OCR confidence | 190933_Kiku.mp4 · 197.413 |
| ホロの乗（ホロライブ切り抜き] | label only; low OCR confidence | 190933_Kiku.mp4 · 83.627 |
| ジャパニズム（大谷翔平ファンCH) | label only; low OCR confidence | 190933_Kiku.mp4 · 81.564 |
| 山田の雑学ch | label only; low OCR confidence | 190933_Kiku.mp4 · 145.217 |
| ドラマみたいだ | label only | 190933_Kiku.mp4 · 337.145 |
| バズワールド | label only | 190933_Kiku.mp4 · 158.899 |
| Google Japan | label only | 190933_Kiku.mp4 · 394.567 |
| ニジカケチューブ | label only | 190933_Kiku.mp4 · 245.853 |
| ポテト王国 | label only | 190933_Kiku.mp4 · 15.232 |
| パワーチューブ | label only | 190933_Kiku.mp4 · 54.817 |
| 世界のびっくり映像館 | label only | 190933_Kiku.mp4 · 565.406 |
| やす太郎 | label only | 190933_Kiku.mp4 · 95.468 |
| リアルフットボール | label only | 190933_Kiku.mp4 · 237.595 |
| ねこの手かりたい | label only | 190933_Kiku.mp4 · 506.344 |
| バズりの殿堂 | label only | 190933_Kiku.mp4 · 67.16 |
| 横山天音チャンネル | label only | 190933_Kiku.mp4 · 76.409 |
| おしのたまご | label only | 190933_Kiku.mp4 · 230.372 |
| ElowenBrook | label only | 190933_Kiku.mp4 · 79.503 |
| 関西ファイトクラブ | label only | 190933_Kiku.mp4 · 378.93 |
| BATTLE INSIGHT | label only | 190933_Kiku.mp4 · 176.534 |
| あるある市立りょうじ小学校 | label only | 190933_Kiku.mp4 · 168.329 |
| 1分ヒーリング | label only | 190933_Kiku.mp4 · 279.836 |
| くぜりな | label only | 190933_Kiku.mp4 · 47.631 |
| 世界のレビュー | label only | 190933_Kiku.mp4 · 277.82 |
| なぜこうなる | label only | 190933_Kiku.mp4 · 45.569 |
| 防災革命 | label only | 190933_Kiku.mp4 · 394.567 |
| MACHUひかりまちゅ | label only | 190933_Kiku.mp4 · 12.638 |
| アオハル狂 | label only | 190933_Kiku.mp4 · 156.546 |
| QuizKnock | label only | 190933_Kiku.mp4 · 112.885 |
| 世界をのぞき見! | UCbP08HY2gO6vx9-DmLtIXWQ | 190933_Kiku.mp4 · 53.286 |
| Hanaの暮らし | UCssjzDdjGMyf2EUInLKEx3Q | 190933_Kiku.mp4 · 305.899 |
| マサーシー | label only | 190933_Kiku.mp4 · 196.897 |
| ぱんお。 | label only | 190933_Kiku.mp4 · 388.482 |
| [Gymnastics]Shidaks | label only | 190933_Kiku.mp4 · 42.991 |
| 溜めて解放チャンネル | label only | 190933_Kiku.mp4 · 202.088 |
| Gokko Club | label only | 190933_Kiku.mp4 · 131.354 |
| Stardy-河野玄斗の神授業 | label only | 190933_Kiku.mp4 · 77.955 |
| グッデイDIY | label only | 190933_Kiku.mp4 · 317.706 |
| ティアロ疾風伝 | label only | 190933_Kiku.mp4 · 188.481 |
| 焼鳥どんの飲食店あるあるチャンネル | label only | 190933_Kiku.mp4 · 64.083 |
| 週末キャンプチャンネル。 | label only | 190933_Kiku.mp4 · 330.37 |
| qwe | label only | 190933_Kiku.mp4 · 683.994 |
| Raia I ASMR | label only | 190933_Kiku.mp4 · 36.822 |
| サツマカワRPGらしさ | label only | 190933_Kiku.mp4 · 127.777 |
| あおぎ り 高校 - Aogiri Vtuber High School | UCPLeqi7rIqS9uY4_TrSUOMg | 190933_Kiku.mp4 · 343.761 |
| コメディラボ(爆笑シーンまとめ1 | label only | 190933_Kiku.mp4 · 50.725 |
| テイム芝生好き雑草ハンター | label only | 190933_Kiku.mp4 · 200.557 |
| だれウマ(料理研究家] | label only | 190933_Kiku.mp4 · 59.989 |
| ゆ～ちょぱ | label only; low OCR confidence | 190933_Kiku.mp4 · 60.505 |
| 昭和スタ一再発見 | label only; low OCR confidence | 190933_Kiku.mp4 · 362.523 |
| アルル | label only | 190933_Kiku.mp4 · 347.84 |
| フィルムの記憶 | label only | 190933_Kiku.mp4 · 71.268 |
| 共感スイッチ | label only | 190933_Kiku.mp4 · 55.333 |
| 秋名山 | label only | 190933_Kiku.mp4 · 224.727 |
| マイ部アニメ | label only | 190933_Kiku.mp4 · 238.111 |
| 1分だけ | label only | 190933_Kiku.mp4 · 117.493 |
| Neet Hideyoshi | label only | 190933_Kiku.mp4 · 182.693 |
| スーツ背広チャンネル | label only | 190933_Kiku.mp4 · 542.883 |
| The Power of Questions | label only | 190933_Kiku.mp4 · 479.803 |
| 僕はバズ | label only | 190933_Kiku.mp4 · 151.373 |
| Deniz Chandhu | label only | 190933_Kiku.mp4 · 193.189 |
| 草生える | label only | 190933_Kiku.mp4 · 118.009 |
| バレー徹底解説チャンネル | label only | 190933_Kiku.mp4 · 133.401 |
| フェルちゃんねる | label only | 190933_Kiku.mp4 · 97.514 |
| MUZOU | label only | 190933_Kiku.mp4 · 67.676 |
| トムのエサ | label only | 190933_Kiku.mp4 · 106.23 |
| ボチリスト | label only | 190933_Kiku.mp4 · 553.475 |
| くらしのマーケット大学 | label only | 190933_Kiku.mp4 · 127.777 |
| サポ魂 | label only | 190933_Kiku.mp4 · 49.178 |
| TMSアニメ公式チャンネル | label only | 190933_Kiku.mp4 · 28.087 |
| なつめあおい | label only | 190933_Kiku.mp4 · 5.953 |
| ゆにのビビり実況 | label only | 190933_Kiku.mp4 · 149.327 |
| おもろい動画 | label only | 190933_Kiku.mp4 · 94.437 |
| 錬磨 | UCCkbGVWX9Gam997CLqzXY0g | 190933_Kiku.mp4 · 71.268 |
| しょうちゃんネル | label only | 190933_Kiku.mp4 · 167.813 |
| YASU Road | label only | 190933_Kiku.mp4 · 121.603 |
| まほりあんず | label only | 190933_Kiku.mp4 · 517.371 |
| ぶいすぽにっき | label only | 190933_Kiku.mp4 · 126.262 |
| マッチング馬場チャンネル | label only | 190933_Kiku.mp4 · 23.964 |
| Make up GYUTAE | label only | 190933_Kiku.mp4 · 241.692 |
| わんさん共働きパパのミニマルライフ | label only | 190933_Kiku.mp4 · 427.973 |
| 元保育士たいこの保育士あるある劇場 | label only | 190933_Kiku.mp4 · 38.867 |
| きょんぺい | label only | 190933_Kiku.mp4 · 181.661 |
| れいなのSNSフリーランス・副業相談室 | label only | 190933_Kiku.mp4 · 262.529 |
| Comma_yuu | label only | 190933_Kiku.mp4 · 3.377 |
| ゆうにゃん | label only | 190933_Kiku.mp4 · 69.722 |
| しゅんぴーファミリー | label only | 190933_Kiku.mp4 · 102.138 |
| 陰キャの憧れ | label only | 190933_Kiku.mp4 · 21.901 |
| 格闘ワン | label only | 190933_Kiku.mp4 · 526.429 |
| Mr.コブシ | label only | 190933_Kiku.mp4 · 20.372 |
| はじめしゃちょ-（hajime) | label only | 190933_Kiku.mp4 · 71.785 |
| ミステリー劇場 | label only | 190933_Kiku.mp4 · 35.29 |
| Vlipok. | label only | 190933_Kiku.mp4 · 58.443 |
| コスメフタちゃんねるサラ | label only | 190933_Kiku.mp4 · 106.23 |
| 福神漬（VTuber切り抜き』 | label only | 190933_Kiku.mp4 · 388.983 |
| 地理でいこーよ | label only | 190933_Kiku.mp4 · 104.2 |
| バスケの笑える怪物[NBAおもしろ] | label only | 190933_Kiku.mp4 · 252.11 |
| ちゃまはし（アニメ・声優] | UCM_9oMuHmuJY2l6hzJcvwvw | 190933_Kiku.mp4 · 277.304 |
| サンリオキャラクターズ[公式』 | label only | 190933_Kiku.mp4 · 116.478 |
| だいじろーDairo | label only | 190933_Kiku.mp4 · 127.277 |
| アニフタ榊原社長 | label only; low OCR confidence | 190933_Kiku.mp4 · 21.386 |
| [公式』キャリカミ | label only; low OCR confidence | 190933_Kiku.mp4 · 42.476 |
| まるみキッチン(簡単レシピ1 | label only; low OCR confidence | 190933_Kiku.mp4 · 170.393 |
| 道トラ（カズトのキャンプ旅]DoTra（Ka... | partial name; low OCR confidence | 190933_Kiku.mp4 · 419.241 |
| けんご三小説紹介（紙上健吾」 | label only; low OCR confidence | 190933_Kiku.mp4 · 0.0 |
| の住人ピエ口哲学) | label only; low OCR confidence | 190933_Kiku.mp4 · 232.483 |
| トリビアン | UCsToy27Ug50dXxvnTsKgeZw | 190933_Kiku.mp4 · 84.657 |
| 飯テロチャンネル | label only | 190933_Kiku.mp4 · 45.054 |
| 琴葉姉妹の放課後 | label only | 190933_Kiku.mp4 · 342.759 |
| Uhrmacher Madon | label only | 190933_Kiku.mp4 · 607.263 |
| 豆知識お兄さん | label only | 190933_Kiku.mp4 · 222.695 |
| 観たくなる | label only | 190933_Kiku.mp4 · 22.417 |
| かいと | label only | 190933_Kiku.mp4 · 34.259 |
| マルスクープ | label only | 190933_Kiku.mp4 · 627.923 |
| 新潟の工場女子 | label only | 190933_Kiku.mp4 · 104.7 |
| かえぽん | label only | 190933_Kiku.mp4 · 351.376 |
| ホラー・都市伝説・裏設定の雑学 | label only | 190933_Kiku.mp4 · 208.747 |
| しゅうと | label only | 190933_Kiku.mp4 · 89.812 |
| 絶対監視彼女 | label only | 190933_Kiku.mp4 · 307.431 |
| 暇つぶしになる雑学 | label only | 190933_Kiku.mp4 · 403.715 |
| 水面れたす | label only | 190933_Kiku.mp4 · 697.159 |
| そろ谷のアニメっち | label only | 190933_Kiku.mp4 · 94.437 |
| キャリ女子の9時から5時 | label only | 190933_Kiku.mp4 · 6.469 |
| 名無し | label only | 190933_Kiku.mp4 · 32.728 |
| 都のオワリですチャンネル | label only | 190933_Kiku.mp4 · 107.246 |
| カリンリキ | label only | 190933_Kiku.mp4 · 285.433 |
| ふじやま家族 | UCdth2hRuLga96-K0DOCeMgg | 190933_Kiku.mp4 · 434.041 |
| ゆみみンゴTV | label only | 190933_Kiku.mp4 · 530.967 |
| とら先生ズ1365日開いてる小児科 | label only | 190933_Kiku.mp4 · 413.995 |
| おもしろ地理雑学 | label only | 190933_Kiku.mp4 · 55.333 |
| マインドスパーク | label only | 190933_Kiku.mp4 · 39.383 |
| いつもみてるぞ好きなもの切り抜き | label only | 190933_Kiku.mp4 · 272.224 |
| May4/メイフォー | label only | 190933_Kiku.mp4 · 361.522 |
| 美肌睡眠研究所天パ先生おさむちゃん | label only | 190933_Kiku.mp4 · 178.581 |
| みうみう。はんなり京都TV | label only | 190933_Kiku.mp4 · 649.924 |
| いぶよヘスカッシュ | label only | 190933_Kiku.mp4 · 197.928 |
| 健康オタクの聖徳太子 | label only | 190933_Kiku.mp4 · 0.0 |
| ゆわももチャンネル | label only | 190933_Kiku.mp4 · 103.685 |
| Syokoyamito(ショーコヤミート) | label only | 190933_Kiku.mp4 · 470.118 |
| Lippo | label only; uncertain glyphs | 190933_Kiku.mp4 · 219.131 |
| 声優って妻いよねっ〔声優・アニメ・漫画.. | partial name | 190933_Kiku.mp4 · 512.35 |
| 美声ジャイアン | label only | 190933_Kiku.mp4 · 98.544 |
| ザワつく!おもしろ図鑑 | label only | 190933_Kiku.mp4 · 275.788 |
| タイムストップ | label only | 190933_Kiku.mp4 · 404.732 |
| HAACHAMA CH 赤井はあと | label only | 190933_Kiku.mp4 · 7.999 |
| カプサイ爺の日常 | label only | 190933_Kiku.mp4 · 286.949 |
| 公共おもしろジャパン(非公式) | label only | 190933_Kiku.mp4 · 39.898 |
| Muhammad Umar | label only | 190933_Kiku.mp4 · 87.751 |
| NBCUniversal Anime/Music | label only | 190933_Kiku.mp4 · 67.16 |
| CAMCAM24〔世界のリアル映像アーカイ.. | partial name | 190933_Kiku.mp4 · 247.401 |
| そらベジ・ガーデンハック | label only | 190933_Kiku.mp4 · 160.431 |
| おーがすと | label only | 190933_Kiku.mp4 · 335.08 |
| WIRED.jp | label only | 190933_Kiku.mp4 · 6.972 |
| ぜろまるペッツ | label only | 190933_Kiku.mp4 · 107.76 |
| Tyler&Yuta 笑って学べる英会話aitem | label only | 190933_Kiku.mp4 · 188.481 |
| こうじ先生＠大学受験pispis | label only | 190933_Kiku.mp4 · 68.191 |
| ノッコン寺田(150キロラガーマン] | label only | 190933_Kiku.mp4 · 70.238 |
| まつざきみお・コスメ、美容動画 | label only | 190933_Kiku.mp4 · 3.891 |
| の住人ピエロ(哲学) | label only | 190933_Kiku.mp4 · 233.0 |
| Take ＆ MeiStory たけめい スト-リ -- | label only | 190933_Kiku.mp4 · 190.013 |
| V好きの一般人 | label only; low OCR confidence | 190933_Kiku.mp4 · 138.527 |
| ささT元教師 | label only; low OCR confidence | 190933_Kiku.mp4 · 259.965 |
| たろーです受験] | label only; low OCR confidence | 190933_Kiku.mp4 · 611.414 |
| ジョカ | label only; low OCR confidence | 190933_Kiku.mp4 · 346.824 |
| なるねぇ（笑けるダイエット] | label only | 190933_Kiku.mp4 · 69.206 |
| Bari(手描き切り抜き] | label only; low OCR confidence | 190933_Kiku.mp4 · 254.691 |
| 田舎民カイジ（Shorts] | UC2dWSCQluKtkppFXLQAp0vQ; low OCR confidence | 190933_Kiku.mp4 · 62.036 |
| にゅう部（公認] | label only; low OCR confidence | 190933_Kiku.mp4 · 326.804 |
| なんか気持ちいい | label only | 190933_Kiku.mp4 · 52.271 |
| ミニセカ | label only | 190933_Kiku.mp4 · 197.928 |
| 犬に負けた魔王 | label only | 190933_Kiku.mp4 · 327.321 |
| ドズル社 | label only | 190933_Kiku.mp4 · 370.654 |
| Kenta's kitchen | label only | 190933_Kiku.mp4 · 45.054 |
| Fischer's | label only | 190933_Kiku.mp4 · 222.695 |
| Edit Zephyrix | label only | 190933_Kiku.mp4 · 89.812 |
| ブスモテ無双ちゃん | label only | 190933_Kiku.mp4 · 683.492 |
| るかさき | label only | 190933_Kiku.mp4 · 169.361 |
| れなまま〻親子で楽しむおうち遊び | label only | 190933_Kiku.mp4 · 8.515 |
| 全部見て | label only | 190933_Kiku.mp4 · 694.51 |
| 心ときめく日本 | label only | 190933_Kiku.mp4 · 299.802 |
| 週刊少女 | label only | 190933_Kiku.mp4 · 148.81 |
| なおすけ | label only | 190933_Kiku.mp4 · 229.871 |
| やまかわてるき | UCdd64FlemydZH2Xq1PsmCAA | 190933_Kiku.mp4 · 63.067 |
| リサの速攻雑学 | label only | 190933_Kiku.mp4 · 138.011 |
| 深夜ドラマ箱 | label only | 190933_Kiku.mp4 · 29.634 |
| サンバ夫婦の日常 | label only | 190933_Kiku.mp4 · 137.511 |
| しまうま劇場 | label only | 190933_Kiku.mp4 · 68.191 |
| にじ速っ | label only | 190933_Kiku.mp4 · 94.437 |
| MDAskater | label only | 190933_Kiku.mp4 · 109.291 |
| ネタめし | label only | 190933_Kiku.mp4 · 147.263 |
| 伝説の瞬間 | label only | 190933_Kiku.mp4 · 646.273 |
| ケーポたんてい | label only | 190933_Kiku.mp4 · 184.225 |
| ITEMONE | label only | 190933_Kiku.mp4 · 409.799 |
| ショートスマイル | label only | 190933_Kiku.mp4 · 44.022 |
| Dr. Zion Kabasawa | label only | 190933_Kiku.mp4 · 29.118 |
| Nghi Nguyen | label only | 190933_Kiku.mp4 · 194.753 |
| 有名になりたい | label only | 190933_Kiku.mp4 · 526.429 |
| SechuRadio | label only | 190933_Kiku.mp4 · 209.779 |
| 一分オタク | label only | 190933_Kiku.mp4 · 439.255 |
| 雑学と衝撃のお部屋 | label only | 190933_Kiku.mp4 · 663.963 |
| ゆるっと、ひつまぶし | label only | 190933_Kiku.mp4 · 533.5 |
| 好きの一般人 | label only | 190933_Kiku.mp4 · 138.011 |
| 名作アーカイブ | label only | 190933_Kiku.mp4 · 135.98 |
| ロッキー芸能チャンネル | label only | 190933_Kiku.mp4 · 374.735 |
| 燻製職人服部 | label only | 190933_Kiku.mp4 · 718.79 |
| 激闘キングチャンネル | label only | 190933_Kiku.mp4 · 649.423 |
| 長野グルメぐり | label only | 190933_Kiku.mp4 · 409.799 |
| 実況ベイビー | label only | 190933_Kiku.mp4 · 22.417 |
| 時雨 | label only | 190933_Kiku.mp4 · 55.333 |
| 参教育の瞬間 | label only | 190933_Kiku.mp4 · 85.173 |
| ネタは突然に | label only | 190933_Kiku.mp4 · 99.061 |
| たえたそちゃんねる | label only | 190933_Kiku.mp4 · 405.733 |
| 名門のオキテ! | label only | 190933_Kiku.mp4 · 73.846 |
| 東海旅 | label only | 190933_Kiku.mp4 · 62.552 |
| アニメ漫画トレンド屋 | label only | 190933_Kiku.mp4 · 16.779 |
| タロー・トレーニング強化書 | label only | 190933_Kiku.mp4 · 188.996 |
| なぜこれ | label only | 190933_Kiku.mp4 · 329.87 |
| フラミンゴの介護予防チャンネル | label only | 190933_Kiku.mp4 · 596.442 |
| 機場空論 | label only | 190933_Kiku.mp4 · 357.473 |
| 世界ビックリ雑学 | label only | 190933_Kiku.mp4 · 520.922 |
| ダーマスちゃんねる | label only | 190933_Kiku.mp4 · 515.837 |
| ひつじかぶりつきごはん | label only | 190933_Kiku.mp4 · 352.391 |
| ムホホ劇場 | label only | 190933_Kiku.mp4 · 265.562 |
| マグロの刺し身 | label only | 190933_Kiku.mp4 · 327.321 |
| ペンギンランカー | label only | 190933_Kiku.mp4 · 146.747 |
| 紫藤乃やニ婚活サポート | label only | 190933_Kiku.mp4 · 270.691 |
| ハゲップル hageple | label only | 190933_Kiku.mp4 · 520.922 |
| 毎日幸せに暮らしましょう。 | label only | 190933_Kiku.mp4 · 268.626 |
| みお-末 | label only | 190933_Kiku.mp4 · 178.066 |
| たあちい夫婦のアソビバ | label only | 190933_Kiku.mp4 · 370.654 |
| 食卓の時間 | label only | 190933_Kiku.mp4 · 150.872 |
| わんぼあ「あおぎり高校切り抜き | label only | 190933_Kiku.mp4 · 557.624 |
| Hyzi_ハイジ | label only | 190933_Kiku.mp4 · 418.74 |
| みづきだヨchannel | label only | 190933_Kiku.mp4 · 108.261 |
| ミツヤスエットノフィギュアCh. | label only | 190933_Kiku.mp4 · 58.959 |
| MrFuji from Japan. | label only | 190933_Kiku.mp4 · 18.841 |
| SunnySide Channelサニーサイドチャンネル | label only | 190933_Kiku.mp4 · 341.728 |
| 神回プレイバック | label only | 190933_Kiku.mp4 · 146.231 |
| World Meets JAPAN | label only | 190933_Kiku.mp4 · 73.846 |
| Pacific League TV Official | label only | 190933_Kiku.mp4 · 24.994 |
| SHOWNAN [しょうなん] | label only | 190933_Kiku.mp4 · 439.755 |
| いち〻不器用さん専用ヘアアレンジ | label only | 190933_Kiku.mp4 · 384.239 |
| 9ちゃん動画 | label only | 190933_Kiku.mp4 · 292.077 |
| R.W.Sドリブル塾　加藤コーチ | label only | 190933_Kiku.mp4 · 156.046 |
| OrangeMagic「本物のオレンジで作るハ.. | partial name | 190933_Kiku.mp4 · 31.697 |
| ぶいすぽっ切り抜き館 | label only | 190933_Kiku.mp4 · 586.333 |
| マサエル MCbattle | label only | 190933_Kiku.mp4 · 460.869 |
| えーねる | label only | 190933_Kiku.mp4 · 491.119 |
| あーずかい | UCaXo5t_49yr6pzFiGtwECpw | 190933_Kiku.mp4 · 229.355 |
| 人生ZIP | label only | 190933_Kiku.mp4 · 697.159 |
| 世界ふしぎ探訪 | label only | 190933_Kiku.mp4 · 622.429 |
| ランクる? | label only | 190933_Kiku.mp4 · 339.694 |
| Monoras [PC-チ] | label only | 190933_Kiku.mp4 · 63.582 |
| 桜 舞兎/Sakura Mau | label only | 190933_Kiku.mp4 · 144.717 |
| たこまる/TAKOMARU | label only | 190933_Kiku.mp4 · 40.414 |
| ささ丁元教師 | label only | 190933_Kiku.mp4 · 280.853 |
| えま！頼りになる☆凍ストック術ど | label only | 190933_Kiku.mp4 · 150.872 |
| 武田塾チャンネル1参考書のやり方・大学. | label only | 190933_Kiku.mp4 · 242.708 |
| MINA釣りちゃんねる「上村美奈』 | label only | 190933_Kiku.mp4 · 483.855 |
| ヘえマジ? | label only | 190933_Kiku.mp4 · 38.352 |
| 蜂なご本店一 | label only | 190933_Kiku.mp4 · 347.325 |
| ホロ助（ホロライブ切り抜き] | label only | 190933_Kiku.mp4 · 512.35 |
| 車屋の本音チャンネル（スタートベース』 | label only | 190933_Kiku.mp4 · 204.152 |
| りゅうちゃんg北の元塾講 | label only; low OCR confidence | 190933_Kiku.mp4 · 209.779 |
| 大阪グルメ〔関西グルメ」公式 | UCgahNwpj1hEKJjXAD4prOIA; low OCR confidence | 190933_Kiku.mp4 · 140.59 |
| THE ROLAND SHOW [公式] | label only; low OCR confidence | 190933_Kiku.mp4 · 99.061 |
| カズチャンネル/Kazu Channel | UCVPz_nauEJpqPxxvYiOpCHQ | 190933_Kiku.mp4 · 410.3 |
| さり(満腹ダイエット) | label only; low OCR confidence | 190933_Kiku.mp4 · 638.342 |
| たいち1ガジェット紹介 | label only; low OCR confidence | 190933_Kiku.mp4 · 502.421 |
| まつも「ソフトテニス失敗研究所] | label only; low OCR confidence | 190933_Kiku.mp4 · 592.905 |
| 昭和スター再発見 | label only; low OCR confidence | 190933_Kiku.mp4 · 362.022 |
| たろ一です受験] | label only; low OCR confidence | 190933_Kiku.mp4 · 614.435 |
| える/Ｅū（にじさんじ] | label only; low OCR confidence | 190933_Kiku.mp4 · 7.484 |
| 附安 | label only; low OCR confidence | 190933_Kiku.mp4 · 183.724 |
| 日本の事実 | label only | 190933_Kiku.mp4 · 167.813 |
| 世界 | label only | 190933_Kiku.mp4 · 64.598 |
| ミガルドア | label only | 190933_Kiku.mp4 · 466.098 |
| 短い世界 | label only | 190933_Kiku.mp4 · 219.631 |
| パーフェクトピギー | label only | 190933_Kiku.mp4 · 16.779 |
| バズるワールド | label only | 190933_Kiku.mp4 · 60.505 |
| 野球記 | label only | 190933_Kiku.mp4 · 339.178 |
| Yura | label only | 190933_Kiku.mp4 · 499.805 |
| 気になる1分 | label only | 190933_Kiku.mp4 · 77.439 |
| Mainichi Genki | label only | 190933_Kiku.mp4 · 207.216 |
| Fiona | label only | 190933_Kiku.mp4 · 177.566 |
| Japansportstimes | label only | 190933_Kiku.mp4 · 203.637 |
| Japanese Animator Mr.Gobunme | label only | 190933_Kiku.mp4 · 706.739 |
| If Box Fantasy | label only | 190933_Kiku.mp4 · 628.439 |
| NobuMovie | label only | 190933_Kiku.mp4 · 292.592 |
| コールセンター本能寺 | label only | 190933_Kiku.mp4 · 515.837 |
| Lilisa38 | label only | 190933_Kiku.mp4 · 579.036 |
| どうぶつのじかん | label only | 190933_Kiku.mp4 · 228.339 |
| 知らなかった | label only | 190933_Kiku.mp4 · 563.001 |
| 1日1分 | label only | 190933_Kiku.mp4 · 378.415 |
| 管理人ちい | label only | 190933_Kiku.mp4 · 581.198 |
| ノモトヒロキ | label only | 190933_Kiku.mp4 · 158.899 |
| フォートナイト初心者育成チャンネル | label only | 190933_Kiku.mp4 · 352.891 |
| サッカー革命家チキン | label only | 190933_Kiku.mp4 · 193.189 |
| ナミちゃんの芸能解説 | label only | 190933_Kiku.mp4 · 496.22 |
| まめ速 | label only | 190933_Kiku.mp4 · 638.843 |
| Grzesiek Zal | label only | 190933_Kiku.mp4 · 586.833 |
| それホント | label only | 190933_Kiku.mp4 · 16.263 |
| 全部教えたる | label only | 190933_Kiku.mp4 · 619.925 |
| ブラックチャンネル | label only | 190933_Kiku.mp4 · 11.092 |
| 元盛てゃんねるる | label only | 190933_Kiku.mp4 · 83.11 |
| アオイホーム | label only | 190933_Kiku.mp4 · 479.803 |
| 神様(ほんもの) | label only | 190933_Kiku.mp4 · 436.22 |
| JYURIANの語り部屋 | label only | 190933_Kiku.mp4 · 218.631 |
| 釣る者達 | label only | 190933_Kiku.mp4 · 260.48 |
| マネビヤ | label only | 190933_Kiku.mp4 · 608.264 |
| 思考アーカイブ | label only | 190933_Kiku.mp4 · 680.487 |
| やんばるゼミ | label only | 190933_Kiku.mp4 · 37.852 |
| 笑いを届ける人 | label only | 190933_Kiku.mp4 · 659.197 |
| 大谷ドリーム日の丸 | label only | 190933_Kiku.mp4 · 372.686 |
| 株式会社オープンリーチ | label only | 190933_Kiku.mp4 · 116.478 |
| いしかわかずや | label only | 190933_Kiku.mp4 · 605.066 |
| 知識ひとさじ | label only | 190933_Kiku.mp4 · 563.001 |
| Chung Khang | label only | 190933_Kiku.mp4 · 18.325 |
| デカデカ!デカボー | label only | 190933_Kiku.mp4 · 217.1 |
| gurigen | label only | 190933_Kiku.mp4 · 117.493 |
| レッチャンネル | UCdyCaOErTQW6feag_lNLSZw | 190933_Kiku.mp4 · 98.029 |
| 夫が寝たあとに公式 | label only | 190933_Kiku.mp4 · 680.487 |
| 知識豚 | label only | 190933_Kiku.mp4 · 326.804 |
| りりの淡色デスクライフ | label only | 190933_Kiku.mp4 · 115.962 |
| ヒロの"都市伝説" | label only | 190933_Kiku.mp4 · 111.853 |
| ハ田エミリの日常 | label only | 190933_Kiku.mp4 · 102.653 |
| ここちゃんねる | UCkOrdMTccmYrCEu81csfn9w | 190933_Kiku.mp4 · 275.788 |
| なんでもない日常の雑学 | label only | 190933_Kiku.mp4 · 475.687 |
| 卓キチちゃんねる | label only | 190933_Kiku.mp4 · 86.719 |
| キミノスクール/キミノ高等学院 | label only | 190933_Kiku.mp4 · 455.283 |
| ケチャップチャップ | label only | 190933_Kiku.mp4 · 353.392 |
| 三木恵「心を動かす話し方」 | label only | 190933_Kiku.mp4 · 399.134 |
| これだけ見て | label only | 190933_Kiku.mp4 · 635.838 |
| あおちゃんねる | label only | 190933_Kiku.mp4 · 642.396 |
| まっしゅムービー | label only | 190933_Kiku.mp4 · 191.028 |
| Miwuさんの科学にほん | label only | 190933_Kiku.mp4 · 159.416 |
| これ、いい。 | label only | 190933_Kiku.mp4 · 625.757 |
| 世話係世界のことを話すかかり | label only | 190933_Kiku.mp4 · 184.741 |
| まるころにゃん | label only | 190933_Kiku.mp4 · 447.809 |
| こはる日和。 | label only | 190933_Kiku.mp4 · 146.747 |
| 公式日本料理てら岡 | label only | 190933_Kiku.mp4 · 260.981 |
| ゲーミングういじ | label only | 190933_Kiku.mp4 · 619.925 |
| べあもりゆるも | label only | 190933_Kiku.mp4 · 35.29 |
| FACIAL YOGA YASUDA HIROM! | label only | 190933_Kiku.mp4 · 252.61 |
| ネタバースチャンネル | label only | 190933_Kiku.mp4 · 560.385 |
| 妻の独り言 | label only | 190933_Kiku.mp4 · 5.438 |
| なち_30秒で分かるワーママのキレイが続.. | partial name | 190933_Kiku.mp4 · 104.2 |
| あつ森劇場未来テレビ | label only | 190933_Kiku.mp4 · 312.641 |
| Suzukikun | label only | 190933_Kiku.mp4 · 443.773 |
| タチバナさんの毎日ルーティン | label only | 190933_Kiku.mp4 · 112.885 |
| Happy Days Shiori | label only | 190933_Kiku.mp4 · 64.083 |
| ユーリsk8 | label only | 190933_Kiku.mp4 · 29.634 |
| 面接官の本音。 | label only | 190933_Kiku.mp4 · 509.718 |
| きょうきみファミリー | label only | 190933_Kiku.mp4 · 230.372 |
| つばさ tsubasa | label only | 190933_Kiku.mp4 · 664.463 |
| 毎日しんちゃん | UC4sdr7xet82Muu62E9I4mNw | 190933_Kiku.mp4 · 36.822 |
| TRIFLE | label only | 190933_Kiku.mp4 · 303.334 |
| すまきっちゃん超 | label only | 190933_Kiku.mp4 · 209.264 |
| 車クロニクル | label only | 190933_Kiku.mp4 · 13.154 |
| エマスちゃんねる/EMASCHANNEL | label only | 190933_Kiku.mp4 · 128.292 |
| トキ北欧風な部屋暮らし | label only | 190933_Kiku.mp4 · 565.406 |
| 農家伝!家庭菜園らいふ | label only | 190933_Kiku.mp4 · 427.472 |
| duly | label only | 190933_Kiku.mp4 · 116.978 |
| 楽待 RAKUMACHI | label only | 190933_Kiku.mp4 · 149.842 |
| りんご自由帳 illustration&art | label only | 190933_Kiku.mp4 · 292.592 |
| Plant Stories | label only | 190933_Kiku.mp4 · 281.373 |
| ジロイモ交通 | label only | 190933_Kiku.mp4 · 69.722 |
| 小沼広太のいやどーも!チャンネル | label only | 190933_Kiku.mp4 · 565.406 |
| ぱん〻忙しいママのための簡単そうじ術 | label only | 190933_Kiku.mp4 · 516.337 |
| せつな | label only | 190933_Kiku.mp4 · 44.538 |
| ハピバニchanne! | label only | 190933_Kiku.mp4 · 96.998 |
| 大魔王[Youtuber・Tiktoker・有名人・芸能... | partial name | 190933_Kiku.mp4 · 282.385 |
| EGA.channel | label only | 190933_Kiku.mp4 · 460.869 |
| おばちゃん教師のあるあるコント(寺門真吾) | label only | 190933_Kiku.mp4 · 331.386 |
| テレ東スポーツ | label only | 190933_Kiku.mp4 · 688.548 |
| ほっとタイム。 | label only | 190933_Kiku.mp4 · 260.48 |
| 社員の声を聞きすぎる会社株式会社ROD.. | partial name | 190933_Kiku.mp4 · 135.464 |
| FOR ALL FIGHTER | label only | 190933_Kiku.mp4 · 586.833 |
| 健康美ピラティストレーナーさち | label only | 190933_Kiku.mp4 · 443.773 |
| やまだ1旅するクリエイター | label only | 190933_Kiku.mp4 · 88.781 |
| 美容整体のうちやま先生。「プラスフィー. | label only | 190933_Kiku.mp4 · 366.604 |
| Lacampin たくむ ラキャンピン | label only | 190933_Kiku.mp4 · 239.128 |
| シクフォニ[SIXFONIA] | label only | 190933_Kiku.mp4 · 88.267 |
| ようすけ1iPhoneとモノで快適な暮らし | label only | 190933_Kiku.mp4 · 512.35 |
| Bytheway. | label only | 190933_Kiku.mp4 · 161.462 |
| 今古賀翔（トレーニング科学』 | label only | 190933_Kiku.mp4 · 112.37 |
| なんでもスポーツ | label only | 190933_Kiku.mp4 · 495.705 |
| 樋口楓（にじさんじ所属] | label only | 190933_Kiku.mp4 · 51.756 |
| hutuntun | label only | 190933_Kiku.mp4 · 560.385 |
| ええしすたいむ＠世界一面白い三姉妹 | label only | 190933_Kiku.mp4 · 464.081 |
| そるとiPhone便利機能ガジェット | label only | 190933_Kiku.mp4 · 223.695 |
| LaughLab | label only | 190933_Kiku.mp4 · 40.414 |
| mizuno yuka水野 祐香 | label only | 190933_Kiku.mp4 · 669.486 |
| あまとガジェットのある暮らし | label only | 190933_Kiku.mp4 · 475.687 |
| えり！親子で楽しむおうち遊び | UCkfFQt4QltWrkV2A62auoHw | 190933_Kiku.mp4 · 120.572 |
| ひなてや🐣 | label only | 190933_Kiku.mp4 · 293.093 |
| ABEMA 恋する週末ホームステイ[公式』 | UCe816MskSn1I90H02pVzHTg | 190933_Kiku.mp4 · 239.128 |
| こな〻3児ママの整える×ラクする暮らし🌿 | label only | 190933_Kiku.mp4 · 312.641 |
| 転職picks【キャリカミ】 | label only | 190933_Kiku.mp4 · 661.718 |
| 平良海馬切り抜きch | label only; low OCR confidence | 190933_Kiku.mp4 · 142.653 |
| わたか可愛い追求ちゃん | label only; low OCR confidence | 190933_Kiku.mp4 · 122.619 |
| ほぼタケフサ（Footba] | label only; low OCR confidence | 190933_Kiku.mp4 · 369.137 |
| ちゃらりんこクック | label only; low OCR confidence | 190933_Kiku.mp4 · 295.706 |
| 紫藤乃やこー婚活サポート | label only | 190933_Kiku.mp4 · 182.693 |
| ほっこりショート | label only; low OCR confidence | 190933_Kiku.mp4 · 15.747 |
| なーすけFitness | label only | 190933_Kiku.mp4 · 701.716 |
| 筋トレモンスター | label only; low OCR confidence | 190933_Kiku.mp4 · 596.442 |
| 森山(キャリカミ広報] | label only; low OCR confidence | 190933_Kiku.mp4 · 562.501 |
| TTM_Jp | label only; low OCR confidence | 190933_Kiku.mp4 · 246.37 |
| MySpanishSchool/ 簡単スぺイン語レッス.. | partial name; low OCR confidence | 190933_Kiku.mp4 · 701.716 |
| ヅンギス談!HBC公式YOUTUbe | label only; low OCR confidence | 190933_Kiku.mp4 · 339.694 |
| れなg恋愛 | label only; low OCR confidence | 190933_Kiku.mp4 · 312.641 |
| タイムアタック | label only; low OCR confidence | 190933_Kiku.mp4 · 49.693 |
| amOprinseSs [ZEROPRI/ | label only; low OCR confidence | 190933_Kiku.mp4 · 52.771 |
| AIRDUNK(バスケ雑学] | label only; low OCR confidence | 190933_Kiku.mp4 · 32.213 |
| ごをくんな動画cć | label only | 190933_Kiku.mp4 · 9.03 |
| あめぷら切り抜き【公認】あめんぼぷら… | partial name; low OCR confidence | 190933_Kiku.mp4 · 191.528 |
| テセサクch（公式切り抜き] | label only; low OCR confidence | 190933_Kiku.mp4 · 177.051 |
| ReGLOSS研究所（ホロライブ切り抜き] | label only; low OCR confidence | 190933_Kiku.mp4 · 638.342 |
| まちデラ〔今日好き] | label only; low OCR confidence | 190933_Kiku.mp4 · 42.476 |
| [公式』トライ | label only; low OCR confidence | 190933_Kiku.mp4 · 37.336 |
| あやみるーむつ | label only; low OCR confidence | 190933_Kiku.mp4 · 34.775 |
| みくろ | label only; low OCR confidence | 190933_Kiku.mp4 · 346.31 |
| ののち | label only | 190933_Kiku.mp4 · 348.841 |
| とますん | label only | 190933_Kiku.mp4 · 32.728 |
| アニドパ | label only | 190933_Kiku.mp4 · 387.45 |
| ワームテール・タニアイ | label only | 190933_Kiku.mp4 · 306.916 |
| 楽しいショート | label only | 190933_Kiku.mp4 · 242.708 |
| Buhmann Taboada | label only | 190933_Kiku.mp4 · 186.949 |
| デイリーサッカー | label only | 190933_Kiku.mp4 · 528.964 |
| たかみち店長 | label only | 190933_Kiku.mp4 · 378.93 |
| シャルル・ルーセント | label only | 190933_Kiku.mp4 · 434.556 |
| 古代侍 | label only | 190933_Kiku.mp4 · 81.048 |
| ペットの世界 | label only | 190933_Kiku.mp4 · 44.538 |
| チュウモクノセカイ | label only | 190933_Kiku.mp4 · 130.854 |
| 魚と海の豆知識 | label only | 190933_Kiku.mp4 · 633.69 |
| つくるだけ | label only | 190933_Kiku.mp4 · 132.386 |
| Anne's Crafts | label only | 190933_Kiku.mp4 · 413.479 |
| Shogo Travels Japan | label only | 190933_Kiku.mp4 · 136.496 |
| Mamiyoshi | label only | 190933_Kiku.mp4 · 237.595 |
| あなたの知りたい世界 | label only | 190933_Kiku.mp4 · 460.352 |
| たつみ店長 | label only | 190933_Kiku.mp4 · 26.541 |
| くつずれデイズ | label only | 190933_Kiku.mp4 · 239.128 |
| 世界の物語 | label only | 190933_Kiku.mp4 · 104.7 |
| キイロネコ | label only | 190933_Kiku.mp4 · 659.197 |
| Rinni Tube | label only | 190933_Kiku.mp4 · 118.525 |
| あまね🫧 | label only | 190933_Kiku.mp4 · 352.891 |
| ほんまにローソン | label only | 190933_Kiku.mp4 · 161.462 |
| アニプレックスチャンネル | label only | 190933_Kiku.mp4 · 518.388 |
| Monica Valgueiro | label only | 190933_Kiku.mp4 · 603.548 |
| KOHALON TOKYO | label only | 190933_Kiku.mp4 · 434.556 |
| DriveAtlas | label only | 190933_Kiku.mp4 · 77.439 |
| なんでも話 | label only | 190933_Kiku.mp4 · 343.26 |
| けんき爆笑図鑑 | label only | 190933_Kiku.mp4 · 19.871 |
| FatCat Screens | label only | 190933_Kiku.mp4 · 311.139 |
| さもん | label only | 190933_Kiku.mp4 · 113.4 |
| バズり太郎 | label only | 190933_Kiku.mp4 · 301.319 |
| ガチ日本 | label only | 190933_Kiku.mp4 · 50.725 |
| Legoradio | label only | 190933_Kiku.mp4 · 390.5 |
| トレ韓 | label only | 190933_Kiku.mp4 · 190.013 |
| えま | label only | 190933_Kiku.mp4 · 83.627 |
| ツルツル坊や | label only | 190933_Kiku.mp4 · 381.044 |
| abody | label only | 190933_Kiku.mp4 · 538.199 |
| 転職! | label only | 190933_Kiku.mp4 · 496.22 |
| MOA | label only | 190933_Kiku.mp4 · 165.766 |
| ほぼ谷ショーヘー | label only | 190933_Kiku.mp4 · 29.118 |
| 諦めないアキラ | label only | 190933_Kiku.mp4 · 325.288 |
| ショート・アンビリバボー | label only | 190933_Kiku.mp4 · 497.738 |
| 浮世絵議事録 | label only | 190933_Kiku.mp4 · 23.448 |
| Yukari's Easy Japanese Home Coo... | partial name | 190933_Kiku.mp4 · 200.557 |
| Miorin's Cafe | label only | 190933_Kiku.mp4 · 380.544 |
| ATTSUN TV | label only | 190933_Kiku.mp4 · 168.845 |
| マッチョ先生の運動常識 | label only | 190933_Kiku.mp4 · 526.429 |
| ベースボールブレンド | label only | 190933_Kiku.mp4 · 497.738 |
| ねる 4歳からのわくわくおうち遊び | label only | 190933_Kiku.mp4 · 94.952 |
| ヴェルナーのお漫オ | label only | 190933_Kiku.mp4 · 506.844 |
| からくり | label only | 190933_Kiku.mp4 · 421.774 |
| 子猫のつぶやき | label only | 190933_Kiku.mp4 · 417.207 |
| FlowLife | label only | 190933_Kiku.mp4 · 223.195 |
| 綾波 | label only | 190933_Kiku.mp4 · 21.901 |
| みるめんカップル | label only | 190933_Kiku.mp4 · 413.995 |
| 三津家貴也 | UCQwSBqzlAq-H7GPvv9Hr17A | 190933_Kiku.mp4 · 454.783 |
| 日本の紫陽花 | UCszC2upvnODDYiL99tLFOsQ | 190933_Kiku.mp4 · 58.443 |
| HIRO BEAUTY CHANNEL | label only | 190933_Kiku.mp4 · 455.783 |
| おふじん | label only | 190933_Kiku.mp4 · 78.471 |
| 在るヒナ子 | label only | 190933_Kiku.mp4 · 200.557 |
| 大人のテニス向上委員会 | label only | 190933_Kiku.mp4 · 106.745 |
| 街角スケッチ 陽太 | label only | 190933_Kiku.mp4 · 144.2 |
| 奇跡の瞬間 | label only | 190933_Kiku.mp4 · 675.69 |
| やせるくん | label only | 190933_Kiku.mp4 · 335.6 |
| 石関聖のサッカーに生きるフットサル思考 | label only | 190933_Kiku.mp4 · 630.959 |
| スポーツダイジェストTV | label only | 190933_Kiku.mp4 · 552.474 |
| MR.HIROCARSTUDIO | label only | 190933_Kiku.mp4 · 610.913 |
| SaaaaayaCHANNEL | label only | 190933_Kiku.mp4 · 184.741 |
| Kuzuha Channel | label only | 190933_Kiku.mp4 · 76.924 |
| Wildlife lens | label only | 190933_Kiku.mp4 · 101.622 |
| 慈円ヒルズ | label only | 190933_Kiku.mp4 · 31.181 |
| 伊豆のぬし釣り | UCOhe6qFb96OZorhMnzJOlJQ | 190933_Kiku.mp4 · 444.275 |
| おもち夫婦〻マネするだけ心地いい暮らし | label only | 190933_Kiku.mp4 · 81.564 |
| クレしん日常ラボ | label only | 190933_Kiku.mp4 · 374.735 |
| かずよちゃんねる北海道観光健康.. | partial name | 190933_Kiku.mp4 · 149.327 |
| HIMA HIMA CHANNEL | label only | 190933_Kiku.mp4 · 579.036 |
| ぱぱぱチャンネル | label only | 190933_Kiku.mp4 · 260.981 |
| Igir Gyenes | label only | 190933_Kiku.mp4 · 212.891 |
| 精神科医がこころの病気を解説す.. | partial name | 190933_Kiku.mp4 · 131.87 |
| すみっこ社長 | label only | 190933_Kiku.mp4 · 436.72 |
| VALX山本義徳 筋トレ大学 | label only | 190933_Kiku.mp4 · 497.238 |
| これはどう? | label only | 190933_Kiku.mp4 · 239.128 |
| 野球クラブ | label only | 190933_Kiku.mp4 · 384.239 |
| 世界事件簿 | label only | 190933_Kiku.mp4 · 120.572 |
| 賢者に導くチャンネル | label only | 190933_Kiku.mp4 · 235.031 |
| カルチョTV | label only | 190933_Kiku.mp4 · 354.424 |
| 吉田なるのおうちヨガチャンネル | label only | 190933_Kiku.mp4 · 277.82 |
| こうぴゃろ | label only | 190933_Kiku.mp4 · 549.454 |
| 声真似パレット | label only | 190933_Kiku.mp4 · 348.841 |
| 水島翔の日常 | label only | 190933_Kiku.mp4 · 99.575 |
| 東海オンエア | label only | 190933_Kiku.mp4 · 155.531 |
| リョウの宇宙科学 | label only | 190933_Kiku.mp4 · 20.372 |
| kaorin1031 | label only | 190933_Kiku.mp4 · 400.15 |
| ラファウの反応集 | label only | 190933_Kiku.mp4 · 662.218 |
| 天野友二朗 | label only | 190933_Kiku.mp4 · 193.189 |
| おうちらくらく | label only | 190933_Kiku.mp4 · 291.045 |
| こういう人生がいい | label only | 190933_Kiku.mp4 · 403.199 |
| なんこれ部 | label only | 190933_Kiku.mp4 · 530.967 |
| LIBERTY-リバテイー | label only | 190933_Kiku.mp4 · 455.283 |
| スプリントコーチーテン | label only | 190933_Kiku.mp4 · 494.188 |
| GONの最高の瞬間 | label only | 190933_Kiku.mp4 · 401.167 |
| CBC Documentary | label only | 190933_Kiku.mp4 · 617.794 |
| すぴすく | label only | 190933_Kiku.mp4 · 151.373 |
| 大人プロサーファー川畑邦宏のサ. | label only | 190933_Kiku.mp4 · 489.103 |
| ぬいさんぽ/NUI-SANPO | label only | 190933_Kiku.mp4 · 592.905 |
| じんざべす | label only | 190933_Kiku.mp4 · 331.886 |
| ささっとオタ活 | label only | 190933_Kiku.mp4 · 207.216 |
| OTTOCAST JP | label only | 190933_Kiku.mp4 · 83.627 |
| ソロ旅 | label only | 190933_Kiku.mp4 · 281.373 |
| あやうや \| ふたり暮らしの日常 | label only | 190933_Kiku.mp4 · 568.62 |
| MEGUMIがんばらんラク家事 | label only | 190933_Kiku.mp4 · 109.291 |
| Sana cooking channel | label only | 190933_Kiku.mp4 · 165.766 |
| ヘっぽこ荼碗蒸し | label only | 190933_Kiku.mp4 · 169.361 |
| 世界でshorts | label only | 190933_Kiku.mp4 · 177.051 |
| ホロうさぎ（ホロライブ切り抜き』 | label only | 190933_Kiku.mp4 · 144.717 |
| ミング視点 | label only | 190933_Kiku.mp4 · 50.725 |
| へりゅうむ | label only | 190933_Kiku.mp4 · 22.932 |
| Kai | label only | 190933_Kiku.mp4 · 274.756 |
| オタク二郎 | label only | 190933_Kiku.mp4 · 30.15 |
| yassine azoui | label only | 190933_Kiku.mp4 · 258.948 |
| 2chのたまり場 | label only | 190933_Kiku.mp4 · 142.653 |
| ゆうさくスポーツ | label only | 190933_Kiku.mp4 · 369.637 |
| いっせ | label only | 190933_Kiku.mp4 · 348.841 |
| Tomari Marichannel/ 兎鞠まりちゃんねる | label only | 190933_Kiku.mp4 · 23.964 |
| だまおのモノ×ライフ | label only | 190933_Kiku.mp4 · 294.689 |
| Gami.X | label only | 190933_Kiku.mp4 · 27.056 |
| 馬場早菊BLYNCTENNIS | label only | 190933_Kiku.mp4 · 129.822 |
| ニアの考察漫画アニメ解説] | label only | 190933_Kiku.mp4 · 118.525 |
| 今和職場論争 | label only | 190933_Kiku.mp4 · 565.908 |
| Shotaro I Trip | label only | 190933_Kiku.mp4 · 317.205 |
| GiftJP | UCEYsEFmDXys7G0Ti1ZomqqA | 190933_Kiku.mp4 · 106.23 |
| Zawazawazawa_tv | label only | 190933_Kiku.mp4 · 298.786 |
| 切り抜きもちゃもちゃ | label only | 190933_Kiku.mp4 · 423.275 |
| 世界が惚れたニッポン | label only | 190933_Kiku.mp4 · 290.544 |
| メメントリ「青終高校遊戯部1 | label only | 190933_Kiku.mp4 · 87.235 |
| MayumiAccessoryつ心の温度が2C上がる... | partial name | 190933_Kiku.mp4 · 92.375 |
| 株式会社NAMIE | label only | 190933_Kiku.mp4 · 715.769 |
| BOTTOM GUN | label only | 190933_Kiku.mp4 · 131.87 |
| heaIth ELF・健康運動 | label only | 190933_Kiku.mp4 · 434.041 |
| Irina Kass | label only | 190933_Kiku.mp4 · 667.001 |
| まやおのボドROOM | label only | 190933_Kiku.mp4 · 281.884 |
| さんぽ。【オモシロ調査室】 | label only | 190933_Kiku.mp4 · 337.66 |
| ALLOUTの筋トレHACK〔トレーニングギア... | partial name | 190933_Kiku.mp4 · 303.334 |
| わらぼ（笑って覚える数学教室〕（math cla... | partial name | 190933_Kiku.mp4 · 390.5 |
| 調理師の台所（Chefs Kitchen] Kei | label only | 190933_Kiku.mp4 · 129.822 |
| めざましmedià | label only | 190933_Kiku.mp4 · 10.576 |
| つ一さんとゆっぴ | label only | 190933_Kiku.mp4 · 528.447 |
| 地理でいこ一よ | label only | 190933_Kiku.mp4 · 105.715 |
| うさこま/ファッション着物フタク | label only; low OCR confidence | 190933_Kiku.mp4 · 316.189 |
| みやちゅーぶ | label only; low OCR confidence | 190933_Kiku.mp4 · 122.619 |
| Nepa/ねぱ-る | label only; low OCR confidence | 190933_Kiku.mp4 · 119.025 |
| お話しタイムの鈐木さん | label only; low OCR confidence | 190933_Kiku.mp4 · 373.187 |
| むぎままDIY | label only; low OCR confidence | 190933_Kiku.mp4 · 160.431 |
| Karasu Gaming [公it] | label only | 190933_Kiku.mp4 · 360.522 |
| まるもももからの10万人行きたい | label only; low OCR confidence | 190933_Kiku.mp4 · 23.448 |
| Hikaru（景色フェチの絶景さんぽ] | label only; low OCR confidence | 190933_Kiku.mp4 · 344.277 |
| 健康マニアTV(科学と叡智で健康を守る] | label only; low OCR confidence | 190933_Kiku.mp4 · 579.036 |
| ショートフィルム「瞬間séíju」 | label only | 190933_Kiku.mp4 · 111.853 |
| 史上最高のスタ一達 | label only; low OCR confidence | 190933_Kiku.mp4 · 436.72 |
| [海外Vlog] おさんぽ日記 | label only; low OCR confidence | 190933_Kiku.mp4 · 653.494 |
| ばっちょ | label only; low OCR confidence | 190933_Kiku.mp4 · 51.756 |
| としおを追う(岡田斗司夫切り抜き) | label only; low OCR confidence | 190933_Kiku.mp4 · 100.076 |
| アジーンTV (Aji-nTV) | label only; low OCR confidence | 190933_Kiku.mp4 · 452.346 |
| サカナクション山口一郎の休憩所切り抜. | label only; low OCR confidence | 190933_Kiku.mp4 · 366.103 |
| ViviCH.綺々羅々ヴィヴイ-FLOWGLOW | label only; low OCR confidence | 190933_Kiku.mp4 · 414.495 |
| 莉犬くん【すとぷり】 | label only; low OCR confidence | 190933_Kiku.mp4 · 33.744 |
| 毎日健康Re:Me | label only; low OCR confidence | 190933_Kiku.mp4 · 243.208 |
| 旅好きマン]しおらー | label only; low OCR confidence | 190933_Kiku.mp4 · 718.289 |
| ハマごはん(お手軽レシピ] | label only; low OCR confidence | 190933_Kiku.mp4 · 549.955 |
| ABEMA 恋愛（公式] | label only; low OCR confidence | 190933_Kiku.mp4 · 116.978 |
| ミニマリスト NozOmi | label only; low OCR confidence | 190933_Kiku.mp4 · 211.36 |
| みんち」#Z世代の味方 | label only; low OCR confidence | 190933_Kiku.mp4 · 248.417 |
| 幸せな人生_T0U | label only; low OCR confidence | 190933_Kiku.mp4 · 423.775 |
| 鯨印【切り抜き】 | label only; low OCR confidence | 190933_Kiku.mp4 · 579.036 |
| アニメ大学 | label only | 190933_Kiku.mp4 · 103.685 |
| 水瀬 | label only | 190933_Kiku.mp4 · 292.077 |
| けんたの伝説 | label only | 190933_Kiku.mp4 · 509.202 |
| ベリメニアニマル | label only | 190933_Kiku.mp4 · 356.973 |
| AUEN | label only | 190933_Kiku.mp4 · 442.272 |
| 笑いの時間 | label only | 190933_Kiku.mp4 · 316.189 |
| ココチャンネル | label only | 190933_Kiku.mp4 · 26.025 |
| 地球ギャラリー | label only | 190933_Kiku.mp4 · 547.936 |
| コレ気になる | label only | 190933_Kiku.mp4 · 547.435 |
| アル兄チャンネル | label only | 190933_Kiku.mp4 · 133.401 |
| いりね夜中に手作りしてみるママ | label only | 190933_Kiku.mp4 · 177.051 |
| Photographer Yoshikatsu Yagishita | label only | 190933_Kiku.mp4 · 410.3 |
| ながしまの島 | label only | 190933_Kiku.mp4 · 320.739 |
| 転職社長 | label only | 190933_Kiku.mp4 · 73.846 |
| 地球のナゾ箱 | label only | 190933_Kiku.mp4 · 302.834 |
| 笑いの列島 | label only | 190933_Kiku.mp4 · 336.113 |
| ラスカルと勉強チャンネル | label only | 190933_Kiku.mp4 · 384.239 |
| Gemmaris | label only | 190933_Kiku.mp4 · 311.639 |
| 楽山快川釣食 | label only; uncertain glyphs | 190933_Kiku.mp4 · 63.067 |
| ナガオカの世界 | label only | 190933_Kiku.mp4 · 37.852 |
| 筋肉社長 | label only | 190933_Kiku.mp4 · 446.291 |
| Edit talks | label only | 190933_Kiku.mp4 · 694.009 |
| ニッポン初めまして | label only | 190933_Kiku.mp4 · 82.596 |
| かみしろ町は今日も平和じゃない。 | label only | 190933_Kiku.mp4 · 110.838 |
| 一分間百科 | label only | 190933_Kiku.mp4 · 543.916 |
| 合理的経済人 | label only | 190933_Kiku.mp4 · 408.782 |
| はあちゅう | label only | 190933_Kiku.mp4 · 489.617 |
| ジョナさん | label only | 190933_Kiku.mp4 · 454.783 |
| ShortsCampus | label only | 190933_Kiku.mp4 · 102.653 |
| Erkson Equive | label only | 190933_Kiku.mp4 · 547.435 |
| Pardy Soraya | label only | 190933_Kiku.mp4 · 296.223 |
| くらしのコツ | label only | 190933_Kiku.mp4 · 213.391 |
| ささみキッチン | label only | 190933_Kiku.mp4 · 34.259 |
| まさきちファミリー | label only | 190933_Kiku.mp4 · 478.302 |
| 一分ルーム | label only | 190933_Kiku.mp4 · 495.705 |
| Impression News Channel | label only | 190933_Kiku.mp4 · 242.192 |
| うき本さんち | label only | 190933_Kiku.mp4 · 537.699 |
| Tailor Bird | label only | 190933_Kiku.mp4 · 333.579 |
| まんまの動画 | label only | 190933_Kiku.mp4 · 164.219 |
| 俺の友達がクズすぎる。 | label only | 190933_Kiku.mp4 · 107.246 |
| 推し活ラボ | label only | 190933_Kiku.mp4 · 258.948 |
| RiceBurger Studios - Learn Japane... | partial name | 190933_Kiku.mp4 · 63.067 |
| 50代からのリフトアップ顔ヨガ | label only | 190933_Kiku.mp4 · 71.785 |
| ボリビアの泉 | label only | 190933_Kiku.mp4 · 48.662 |
| ビグムン🙂 | label only | 190933_Kiku.mp4 · 270.691 |
| ガレージ公道最速伝説 | label only | 190933_Kiku.mp4 · 350.859 |
| まじめにヤバシティ | label only | 190933_Kiku.mp4 · 49.693 |
| 物語の余韻 | label only | 190933_Kiku.mp4 · 417.723 |
| ゆるボクチャンネル | label only | 190933_Kiku.mp4 · 91.859 |
| 相原バラ園 | label only | 190933_Kiku.mp4 · 155.531 |
| Noah Sato | label only | 190933_Kiku.mp4 · 285.948 |
| 中華そばみたか | label only | 190933_Kiku.mp4 · 35.791 |
| 倉嶋里菜 | UCOywfV92VIHB2c9EW7Fm8Pg | 190933_Kiku.mp4 · 28.603 |
| サッカージャンキー | label only | 190933_Kiku.mp4 · 647.811 |
| グルメバイトちゃん | label only | 190933_Kiku.mp4 · 84.657 |
| あつみゆうすけ | label only | 190933_Kiku.mp4 · 50.209 |
| 意外と知られていない | label only | 190933_Kiku.mp4 · 423.275 |
| YutchanFamily | label only | 190933_Kiku.mp4 · 478.802 |
| 内なる思考 | label only | 190933_Kiku.mp4 · 543.399 |
| 日テレ鉄道部 | label only | 190933_Kiku.mp4 · 290.544 |
| 小雨 | label only | 190933_Kiku.mp4 · 372.686 |
| 親愛なるJAPAN | label only | 190933_Kiku.mp4 · 329.369 |
| 極限野球 | label only | 190933_Kiku.mp4 · 119.025 |
| 棚から田中 | label only | 190933_Kiku.mp4 · 408.282 |
| おじ転 | label only | 190933_Kiku.mp4 · 150.872 |
| 着物沼への案内人たこすけ | label only | 190933_Kiku.mp4 · 256.238 |
| ワイワイ速報 | label only | 190933_Kiku.mp4 · 330.37 |
| 森本陽 | label only | 190933_Kiku.mp4 · 111.853 |
| ハナぷぅん | label only | 190933_Kiku.mp4 · 206.715 |
| 味噌汁の反乱 | label only | 190933_Kiku.mp4 · 518.388 |
| よへ僕がいい旦那になるまで | UCSHYSrvh9E__9Fs-l4cTpPA | 190933_Kiku.mp4 · 240.677 |
| SONIC LOVE STORY | label only | 190933_Kiku.mp4 · 137.011 |
| ラジコン女子ナナちん&はっち | label only | 190933_Kiku.mp4 · 115.962 |
| 末路ちゃんねる | label only | 190933_Kiku.mp4 · 532.468 |
| なみきゴルフ | label only | 190933_Kiku.mp4 · 262.529 |
| Speedbird loves airplanes and trains. | label only | 190933_Kiku.mp4 · 222.695 |
| CAMP HACK | label only | 190933_Kiku.mp4 · 33.744 |
| あやんぬ🍔🍊 | label only | 190933_Kiku.mp4 · 404.732 |
| クスクス部 | label only | 190933_Kiku.mp4 · 72.3 |
| HamachikoChanne! | label only | 190933_Kiku.mp4 · 707.239 |
| とも整えたいパパの日常 | label only | 190933_Kiku.mp4 · 486.47 |
| うえだしんや界隈 | label only | 190933_Kiku.mp4 · 101.106 |
| 奇跡の1分 | label only | 190933_Kiku.mp4 · 230.372 |
| 動物虫眼鏡 | label only | 190933_Kiku.mp4 · 218.631 |
| あきち | label only | 190933_Kiku.mp4 · 350.358 |
| 世界規模で大バズり | label only | 190933_Kiku.mp4 · 310.108 |
| アサファ・パウエルのファン | label only | 190933_Kiku.mp4 · 221.18 |
| 空から見る世界の神秘 | label only | 190933_Kiku.mp4 · 254.691 |
| ひろんじ.kirinuki | label only | 190933_Kiku.mp4 · 115.447 |
| くらしのヒントアイメディア | label only | 190933_Kiku.mp4 · 297.254 |
| あいり | label only | 190933_Kiku.mp4 · 191.528 |
| えぬやま健康雑学 | label only | 190933_Kiku.mp4 · 48.148 |
| ポップな記憶 | label only | 190933_Kiku.mp4 · 48.148 |
| 健康一番 | label only | 190933_Kiku.mp4 · 63.582 |
| コスメ語りたい倶楽部 | label only | 190933_Kiku.mp4 · 169.877 |
| 境界のパラドックス | label only | 190933_Kiku.mp4 · 655.658 |
| ハル映画 | label only | 190933_Kiku.mp4 · 294.689 |
| 逆転合格専門塾ポラリスアカデミア | label only | 190933_Kiku.mp4 · 290.029 |
| 書店員はなBL漫画紹介 | label only | 190933_Kiku.mp4 · 73.331 |
| ナニコレ探偵団 | label only | 190933_Kiku.mp4 · 296.738 |
| 一分一秒 | label only | 190933_Kiku.mp4 · 377.398 |
| カイセイの九州旅 | label only | 190933_Kiku.mp4 · 351.376 |
| POKY | label only | 190933_Kiku.mp4 · 291.045 |
| ゆるっとスキマ時間 | label only | 190933_Kiku.mp4 · 699.695 |
| テストと受験を詳しく強くするあごなつ.. | partial name | 190933_Kiku.mp4 · 551.472 |
| ウェンデイ | label only | 190933_Kiku.mp4 · 310.624 |
| 競艇フリーダム | label only | 190933_Kiku.mp4 · 196.897 |
| HikakinTV | label only | 190933_Kiku.mp4 · 710.761 |
| めろんぱん氏(にじ切り抜き) | label only | 190933_Kiku.mp4 · 39.383 |
| haruka_kurashi | label only | 190933_Kiku.mp4 · 157.062 |
| Okeisuzumasa | label only | 190933_Kiku.mp4 · 718.79 |
| 1分もふもふ | label only | 190933_Kiku.mp4 · 443.273 |
| hetuntun | label only | 190933_Kiku.mp4 · 246.37 |
| 西園寺切り抜き006号 | label only | 190933_Kiku.mp4 · 120.572 |
| こころ便り | label only | 190933_Kiku.mp4 · 218.631 |
| ズボラの漫画飯再現料理 | label only | 190933_Kiku.mp4 · 284.418 |
| カナウホーム_名古屋不動産 | label only | 190933_Kiku.mp4 · 361.022 |
| クレヨン映画館 | label only | 190933_Kiku.mp4 · 548.939 |
| ayahar. | label only | 190933_Kiku.mp4 · 234.015 |
| よんろくつぶのうちゅう | label only | 190933_Kiku.mp4 · 585.832 |
| メンズメイクLABO | label only | 190933_Kiku.mp4 · 125.761 |
| めりあんず | label only | 190933_Kiku.mp4 · 628.439 |
| TIRO | label only | 190933_Kiku.mp4 · 90.312 |
| すずきゆりあ | label only | 190933_Kiku.mp4 · 567.586 |
| はるか耳鼻科 | label only | 190933_Kiku.mp4 · 73.331 |
| BestKid | label only | 190933_Kiku.mp4 · 208.232 |
| Claudine Tlatelpa | label only | 190933_Kiku.mp4 · 443.773 |
| 30秒スレ解説 | label only | 190933_Kiku.mp4 · 52.271 |
| tomi_stretch | label only | 190933_Kiku.mp4 · 275.788 |
| ペい1分でわかるズル賢い一人暮らし | label only | 190933_Kiku.mp4 · 183.209 |
| ヒカ集 | label only | 190933_Kiku.mp4 · 598.429 |
| ニッポンが好きすぎるんじゃ | label only | 190933_Kiku.mp4 · 320.739 |
| 家づくりナビゲーターたっちゃんねる | label only | 190933_Kiku.mp4 · 310.108 |
| 食べて健康! | label only | 190933_Kiku.mp4 · 272.224 |
| ともよTomoyo | label only | 190933_Kiku.mp4 · 90.312 |
| tomo tomo | label only | 190933_Kiku.mp4 · 425.954 |
| おとたび-大人の旅行- | label only | 190933_Kiku.mp4 · 389.499 |
| 朝鮮Talk | label only | 190933_Kiku.mp4 · 389.499 |
| 吉田直輔/姿勢から整える大人ボディメイク | label only | 190933_Kiku.mp4 · 143.685 |
| そらiphoneカメラで日常を非日常に | label only | 190933_Kiku.mp4 · 54.302 |
| nomu land | label only | 190933_Kiku.mp4 · 569.12 |
| 末期のアーデーハーデ- | label only | 190933_Kiku.mp4 · 163.704 |
| 柴ラン | label only | 190933_Kiku.mp4 · 338.662 |
| 音域を広げる大人のボイトレ〔日本美声チ. | label only | 190933_Kiku.mp4 · 236.58 |
| 異次元スタッツTV | label only | 190933_Kiku.mp4 · 315.689 |
| マサキノジンセイハタノシイ | label only | 190933_Kiku.mp4 · 356.472 |
| Japanese hunter's meal ] ENG sub | label only | 190933_Kiku.mp4 · 145.731 |
| VAIENCE バイエンス | label only | 190933_Kiku.mp4 · 339.178 |
| 名店グルメ1東京発 | label only | 190933_Kiku.mp4 · 124.214 |
| 昭和平成レトロ | label only | 190933_Kiku.mp4 · 183.209 |
| シルシル世界 | label only | 190933_Kiku.mp4 · 207.731 |
| りょう家族が喜ぶラクうまレシピ | label only | 190933_Kiku.mp4 · 408.282 |
| マジワロくん | label only | 190933_Kiku.mp4 · 162.478 |
| りきパパ ママがラクになる家族旅行 | label only | 190933_Kiku.mp4 · 130.854 |
| EichanFamilyえいちゃんファミリー | label only | 190933_Kiku.mp4 · 290.544 |
| ヴァロラント学園りだら～ず | label only | 190933_Kiku.mp4 · 113.4 |
| REGATE D.S. / Football Skills Channel | label only | 190933_Kiku.mp4 · 245.353 |
| みやっちもんちっち | label only | 190933_Kiku.mp4 · 359.505 |
| ローフルズ/ROFLS | label only | 190933_Kiku.mp4 · 135.464 |
| ぽんしばの庭 | label only | 190933_Kiku.mp4 · 638.342 |
| T.V R.W.Sドリブル | label only | 190933_Kiku.mp4 · 24.479 |
| KH / Killin9Hit | label only | 190933_Kiku.mp4 · 246.885 |
| タイム マシーン3号official YouTube Channel | label only | 190933_Kiku.mp4 · 356.973 |
| しゅんダイアリー就活チャンネル | label only | 190933_Kiku.mp4 · 310.108 |
| piko_ beauty | label only | 190933_Kiku.mp4 · 430.005 |
| hinaka | label only | 190933_Kiku.mp4 · 377.398 |
| QuizKnockと学ぼう | label only | 190933_Kiku.mp4 · 346.824 |
| GOLFavoゴルファボ | label only | 190933_Kiku.mp4 · 362.523 |
| ぐりぐらママのおでかけチャンネル☆ | label only | 190933_Kiku.mp4 · 50.209 |
| ホリエモンの禁断トーク【堀江貴文 切り抜… | partial name | 190933_Kiku.mp4 · 246.37 |
| Let's go Nakamu - japanese tourist | label only | 190933_Kiku.mp4 · 590.37 |
| カイチャリスポーツ | label only | 190933_Kiku.mp4 · 490.618 |
| みちけんきゅうじよ | label only | 190933_Kiku.mp4 · 137.011 |
| TBS CROsS DIG with Bloomberg | label only | 190933_Kiku.mp4 · 599.948 |
| なちょ〻10キロ痩せた管理栄養士がつくる簡… | partial name | 190933_Kiku.mp4 · 125.246 |
| 長野県でラジコンを飛ばそう! | UCXVIeB_FmQ8Igro0wN4mVcg | 190933_Kiku.mp4 · 643.463 |
| ショート劇場 | label only | 190933_Kiku.mp4 · 267.094 |
| 小森めと切り抜き（ぶいすぽ』 | label only | 190933_Kiku.mp4 · 543.399 |
| がっけー | label only | 190933_Kiku.mp4 · 278.32 |
| 読書好きのMOMO | label only | 190933_Kiku.mp4 · 233.5 |
| 「からだ塾」セルフケアアドバイスセンター | label only | 190933_Kiku.mp4 · 141.621 |
| 狩棋ニュース速報（元奨全国優勝＆ウォーズ. | label only | 190933_Kiku.mp4 · 92.89 |
| Ghfv Yhg | label only | 190933_Kiku.mp4 · 343.26 |
| じゅり〻整理収納アドバイザー×4児ママ | label only | 190933_Kiku.mp4 · 628.439 |
| ディズニープラネット(雑学1 | label only | 190933_Kiku.mp4 · 88.781 |
| 「ヘビースモーカーの(ほぼ)ドリフ名言師 | label only | 190933_Kiku.mp4 · 325.288 |
| 【SGIR公式】SAM Get It Right切り抜き | label only | 190933_Kiku.mp4 · 664.463 |
| ズボラの掃除ハック:ラテ子olate_cleanlife | label only; low OCR confidence | 190933_Kiku.mp4 · 259.965 |
| 二ふな瀬。:kofunase | label only; low OCR confidence | 190933_Kiku.mp4 · 217.1 |
| 佐久間宣行お笑いチャソネル〔#NOBROCK... | partial name; low OCR confidence | 190933_Kiku.mp4 · 29.118 |
| サッカー中毒 Highlights&lssue | label only | 190933_Kiku.mp4 · 284.418 |
| もろゴル1諸藤将次みんなでゴルフTV | label only; low OCR confidence | 190933_Kiku.mp4 · 158.899 |
| ゴルフレッスン動画　KAZUGOLFchanneI | label only; low OCR confidence | 190933_Kiku.mp4 · 186.434 |
| サイキ \| ガジェットの世界 | label only; low OCR confidence | 190933_Kiku.mp4 · 672.297 |
| マカロンFC♢ | label only; low OCR confidence | 190933_Kiku.mp4 · 56.895 |
| えだまめ口ン | label only; low OCR confidence | 190933_Kiku.mp4 · 539.863 |
| ブ。ーVubeの切り抜きについて一 | label only; low OCR confidence | 190933_Kiku.mp4 · 194.753 |
| レヅスタンス | label only; low OCR confidence | 190933_Kiku.mp4 · 707.741 |
| 名もなき戦闘員no.27 | label only; low OCR confidence | 190933_Kiku.mp4 · 53.286 |
| だんぼ（簡単飯を作る限界サラリーマン』 | label only; low OCR confidence | 190933_Kiku.mp4 · 409.799 |
| ヒロクリ [ひろゆき切り 抜 き]Hiroyuki Clip TV | label only | 190933_Kiku.mp4 · 372.686 |
| 椛/momiji | label only; low OCR confidence | 190933_Kiku.mp4 · 369.637 |
| 小池飯金 | label only; low OCR confidence | 190933_Kiku.mp4 · 102.138 |
| オトナの夜ふかしch | label only; low OCR confidence | 190933_Kiku.mp4 · 111.338 |
| ヨシスタ | label only; low OCR confidence | 190933_Kiku.mp4 · 49.178 |
| ChiloutFishing （チルアウトフイッシング.. | partial name | 190933_Kiku.mp4 · 400.666 |
| 陸海空マシソLAB | label only; low OCR confidence | 190933_Kiku.mp4 · 112.885 |
| 日テレスポーツ【公式】 | label only; low OCR confidence | 190933_Kiku.mp4 · 285.433 |
| スポーツ研究所 | label only; low OCR confidence | 190933_Kiku.mp4 · 332.403 |
| ANPAN KIDS TV ☆ アンパンキッ… | partial name; low OCR confidence | 190933_Kiku.mp4 · 154.499 |
| よしお〔恋愛心理×人間心理] | label only; low OCR confidence | 190933_Kiku.mp4 · 526.429 |
| てろてろ「Vtuber切り抜き』 | label only; low OCR confidence | 190933_Kiku.mp4 · 447.809 |
| ほぼタケフサ【Football】 | label only; low OCR confidence | 190933_Kiku.mp4 · 480.303 |
| DOTホツグ | label only; low OCR confidence | 190933_Kiku.mp4 · 85.173 |
| ヤクヤ [YAkUYA] | label only; low OCR confidence | 190933_Kiku.mp4 · 130.339 |
| DAM(バスケ雑学) | label only; low OCR confidence | 190933_Kiku.mp4 · 251.094 |
| なのch.[Vtuber切り抜き」 | label only; low OCR confidence | 190933_Kiku.mp4 · 524.362 |
| 【SGIR公式】切り抜きfitness | label only; low OCR confidence | 190933_Kiku.mp4 · 381.044 |
| ひかりん♂🍡 | label only; low OCR confidence | 190933_Kiku.mp4 · 25.511 |
| お茶丸（ちょっと笑えるストーリー) | label only; low OCR confidence | 190933_Kiku.mp4 · 28.087 |
| しんや【本との暮らし📚】 | label only; low OCR confidence | 190933_Kiku.mp4 · 278.32 |
| ☆凍子ママ | label only; low OCR confidence | 190933_Kiku.mp4 · 276.804 |
| 美声ジヤイアン | label only; low OCR confidence | 190933_Kiku.mp4 · 98.029 |
| さんど。（よろずや] | label only; low OCR confidence | 190933_Kiku.mp4 · 47.631 |
| DJふおいFAN（切り抜きCh] | label only; low OCR confidence | 190933_Kiku.mp4 · 446.291 |
| [サカナクションクリップ] 山ロー郎 mel.. | partial name; low OCR confidence | 190933_Kiku.mp4 · 438.755 |
| li li ai | label only; low OCR confidence | 190933_Kiku.mp4 · 270.691 |
| RIZIN（切り抜き動画]チャソネル | label only; low OCR confidence | 190933_Kiku.mp4 · 549.955 |
| ぷりっつ | label only; low OCR confidence | 190933_Kiku.mp4 · 378.415 |
| ♡美容インフォ♡ | label only; low OCR confidence | 190933_Kiku.mp4 · 164.734 |
| ぶっくん(V切り抜きch] | label only; low OCR confidence | 190933_Kiku.mp4 · 165.766 |
| アリーナむさし | label only | 190933_Kiku.mp4 · 127.277 |
| Gadget jet | label only | 190933_Kiku.mp4 · 47.116 |
| ミステリーナイトウ | label only | 190933_Kiku.mp4 · 717.788 |
| 世界の筋肉 | label only | 190933_Kiku.mp4 · 511.333 |
| とうでい | label only | 190933_Kiku.mp4 · 268.111 |
| ゴリラチャンネル | label only | 190933_Kiku.mp4 · 632.673 |
| 中村・仕事選びガイド | label only | 190933_Kiku.mp4 · 436.22 |
| Dang Mai | label only | 190933_Kiku.mp4 · 82.08 |
| シネマンガ・ブラザーズ | label only | 190933_Kiku.mp4 · 595.942 |
| 筋肉の部屋 | label only | 190933_Kiku.mp4 · 515.336 |
| セガサミーフェニックス公式チャンネル | label only | 190933_Kiku.mp4 · 111.338 |
| 谷内敦 | label only | 190933_Kiku.mp4 · 233.0 |
| Miho SpeakJapanese | label only | 190933_Kiku.mp4 · 144.717 |
| ガーデニングチャンネル | label only | 190933_Kiku.mp4 · 369.137 |
| Lofing Correra | label only | 190933_Kiku.mp4 · 72.815 |
| 脳筋ショート | label only | 190933_Kiku.mp4 · 706.238 |
| まさやんテイメント | label only | 190933_Kiku.mp4 · 398.633 |
| ゆいのお菓子作り | label only | 190933_Kiku.mp4 · 72.815 |
| 舞流ブル | label only | 190933_Kiku.mp4 · 495.204 |
| Bobby Holmes | label only | 190933_Kiku.mp4 · 76.924 |
| 広い世界のショート | label only | 190933_Kiku.mp4 · 458.834 |
| Feral Living | label only | 190933_Kiku.mp4 · 434.041 |
| 南ティモール | label only | 190933_Kiku.mp4 · 62.552 |
| ハンズ公式 | label only | 190933_Kiku.mp4 · 700.713 |
| Ageta | label only | 190933_Kiku.mp4 · 326.304 |
| HeartTouchJP | label only | 190933_Kiku.mp4 · 63.067 |
| さとこ国立公園 | label only | 190933_Kiku.mp4 · 557.124 |
| れおの逆襲 | label only | 190933_Kiku.mp4 · 610.412 |
| 3分映画部 | label only | 190933_Kiku.mp4 · 347.84 |
| えすてんけ | label only | 190933_Kiku.mp4 · 404.732 |
| 1分後の衝撃 | label only | 190933_Kiku.mp4 · 671.283 |
| ロボカーポリーテレビ | label only | 190933_Kiku.mp4 · 262.529 |
| はるひなちゃんねる | UCwc_LJW44FerVGq-zFcOUBw | 190933_Kiku.mp4 · 649.423 |
| 土日に生きる | label only | 190933_Kiku.mp4 · 263.029 |
| 放課後アオハル学園 | label only | 190933_Kiku.mp4 · 591.904 |
| いいもの図鑑 | label only | 190933_Kiku.mp4 · 640.878 |
| 世界バズ | label only | 190933_Kiku.mp4 · 392.548 |
| TKG | label only | 190933_Kiku.mp4 · 47.631 |
| 女性芸能人豆知識 | label only | 190933_Kiku.mp4 · 473.153 |
| ばにあ | label only | 190933_Kiku.mp4 · 121.087 |
| PDSKabushikiGaisha | label only | 190933_Kiku.mp4 · 648.922 |
| ベースボール雑学 | label only | 190933_Kiku.mp4 · 103.685 |
| ホラー・都市伝説の雑学 | label only | 190933_Kiku.mp4 · 661.218 |
| あの日の放課後 | label only | 190933_Kiku.mp4 · 713.765 |
| 1分健康情報 | label only | 190933_Kiku.mp4 · 562.501 |
| 松の玄関 | label only | 190933_Kiku.mp4 · 330.885 |
| 世界不思議 | label only | 190933_Kiku.mp4 · 578.518 |
| BUMP | label only | 190933_Kiku.mp4 · 499.305 |
| ayaka | label only | 190933_Kiku.mp4 · 599.447 |
| たまらんグルメ | label only | 190933_Kiku.mp4 · 73.331 |
| Ikeda Records | label only | 190933_Kiku.mp4 · 515.837 |
| Little_GiggleLab | label only | 190933_Kiku.mp4 · 668.97 |
| Kapi Lab. | label only | 190933_Kiku.mp4 · 399.649 |
| 一瞬でアート | label only | 190933_Kiku.mp4 · 630.458 |
| 冥河観察 | label only | 190933_Kiku.mp4 · 445.791 |
| ナンバマンンズ | label only; uncertain glyphs | 190933_Kiku.mp4 · 329.87 |
| 元吹部の犬ささけん | label only | 190933_Kiku.mp4 · 655.658 |
| ミリオネア製作所 | label only | 190933_Kiku.mp4 · 658.696 |
| Tnaka | label only | 190933_Kiku.mp4 · 679.986 |
| Adventure with ZEO | label only | 190933_Kiku.mp4 · 403.199 |
| バサラ | label only | 190933_Kiku.mp4 · 226.791 |
| 「ただよび」文系チャンネル | label only | 190933_Kiku.mp4 · 548.438 |
| シネマショート | label only | 190933_Kiku.mp4 · 602.546 |
| リョウカスイングゴルフ | label only | 190933_Kiku.mp4 · 77.955 |
| みな〻親子でハマる全力おうち遊び | label only | 190933_Kiku.mp4 · 445.791 |
| HERNIA COUNTRY STORY | label only | 190933_Kiku.mp4 · 585.832 |
| Minimal streamer YAIBA | label only | 190933_Kiku.mp4 · 493.686 |
| てがみをよむじょせい | label only | 190933_Kiku.mp4 · 706.238 |
| みなもり | label only | 190933_Kiku.mp4 · 366.103 |
| まゆ〻忙しいママでもゆとりある暮らし | label only | 190933_Kiku.mp4 · 230.372 |
| NATSUKIのストレッチTV | label only | 190933_Kiku.mp4 · 589.353 |
| 1分せかバク | label only | 190933_Kiku.mp4 · 225.243 |
| 株式会社す・なお | label only | 190933_Kiku.mp4 · 532.468 |
| [Stop motion Bundodo] Komabun | label only | 190933_Kiku.mp4 · 508.702 |
| 暴走掲示板 | label only | 190933_Kiku.mp4 · 232.483 |
| あやはやチャンネル | label only | 190933_Kiku.mp4 · 438.238 |
| もちもちお | label only | 190933_Kiku.mp4 · 690.846 |
| 恋するニッポン | label only | 190933_Kiku.mp4 · 701.214 |
| あると | label only | 190933_Kiku.mp4 · 709.759 |
| NAKAKO ONEPIECE | label only | 190933_Kiku.mp4 · 518.388 |
| Niji Family Trips | label only | 190933_Kiku.mp4 · 523.862 |
| mochimugi | label only | 190933_Kiku.mp4 · 71.268 |
| Lyssie ASMR | label only | 190933_Kiku.mp4 · 306.916 |
| すず | label only | 190933_Kiku.mp4 · 419.241 |
| ぽぽぽんニッポン | label only | 190933_Kiku.mp4 · 168.845 |
| GQ JAPAN | label only | 190933_Kiku.mp4 · 121.087 |
| 大田ひろゆき | label only | 190933_Kiku.mp4 · 637.84 |
| 極悪特区 | UCYSeks1YPf9b_-l9KR_s16Q | 190933_Kiku.mp4 · 591.904 |
| マツヤマイカ Maika Matsuya | label only | 190933_Kiku.mp4 · 337.145 |
| カナリィ速報 | label only | 190933_Kiku.mp4 · 576.015 |
| 暇つぶし好きな時に見てください | label only | 190933_Kiku.mp4 · 176.534 |
| Sua life | label only | 190933_Kiku.mp4 · 443.273 |
| 航空雑学ラボ | label only | 190933_Kiku.mp4 · 238.111 |
| Compiece [Com. clipping ch] | label only | 190933_Kiku.mp4 · 304.883 |
| かっけ | label only | 190933_Kiku.mp4 · 278.82 |
| スギタク | label only | 190933_Kiku.mp4 · 576.015 |
| Chamo | label only | 190933_Kiku.mp4 · 449.827 |
| おくまんチャンネル | label only | 190933_Kiku.mp4 · 477.801 |
| イヌイサン運動神経の乱用 | label only | 190933_Kiku.mp4 · 245.853 |
| フットボールワールド | label only | 190933_Kiku.mp4 · 369.137 |
| 初めて知った | label only | 190933_Kiku.mp4 · 640.878 |
| いい声ボイトレ研究所 | UCpcQQ_qOFxQt09jKGL6FamQ | 190933_Kiku.mp4 · 595.942 |
| Magosobolgrandma and grandson) | label only | 190933_Kiku.mp4 · 721.488 |
| ランドセル専門店kodomoni. | label only | 190933_Kiku.mp4 · 321.755 |
| レトロバスケ動画 | label only | 190933_Kiku.mp4 · 165.766 |
| YUKINAIオンラインダイエットトレーナー | label only | 190933_Kiku.mp4 · 551.974 |
| とんずら | label only | 190933_Kiku.mp4 · 515.336 |
| 炎の大谷翔平SHOW | label only | 190933_Kiku.mp4 · 661.718 |
| スポーツのあれこれ | label only | 190933_Kiku.mp4 · 98.544 |
| 総合型選抜対策塾ホワイトアカデミー高等部 | label only | 190933_Kiku.mp4 · 583.266 |
| バドミントントレーニング熊の穴! | label only | 190933_Kiku.mp4 · 607.263 |
| にじさんじ公式切り抜きチャンネ… | partial name | 190933_Kiku.mp4 · 688.548 |
| 思わず二度見 | label only | 190933_Kiku.mp4 · 255.723 |
| 勝 友美-VICTORY CHANNEL- | label only | 190933_Kiku.mp4 · 258.948 |
| オムライス兄さん OmuriceBoy | label only | 190933_Kiku.mp4 · 393.55 |
| 今日好き切り抜き部 | label only | 190933_Kiku.mp4 · 399.649 |
| 痛み改善セルフケアCH/理学療法士監修 | label only | 190933_Kiku.mp4 · 285.433 |
| ポールの浪漫 | label only | 190933_Kiku.mp4 · 585.832 |
| いゆぴ/勉強じかんを楽しくデザイン | label only | 190933_Kiku.mp4 · 280.853 |
| バスケットマンへの道 | label only | 190933_Kiku.mp4 · 322.271 |
| 釈迦切り抜きチャンネル | label only | 190933_Kiku.mp4 · 320.238 |
| arupa khanai 2.0 | label only | 190933_Kiku.mp4 · 168.845 |
| クリエイティブの裏側 | label only | 190933_Kiku.mp4 · 81.564 |
| ユジックの手品教室 | label only | 190933_Kiku.mp4 · 483.355 |
| NekoDrama Café | label only | 190933_Kiku.mp4 · 400.15 |
| さわらさん/cluster140 | label only | 190933_Kiku.mp4 · 277.304 |
| コイチルム | label only | 190933_Kiku.mp4 · 501.92 |
| こにょひで夫婦 | label only | 190933_Kiku.mp4 · 144.717 |
| えびズボラでも整うマイペースな暮らし | label only | 190933_Kiku.mp4 · 59.474 |
| ショートスポーツ | label only | 190933_Kiku.mp4 · 264.546 |
| かい \| 1分でわかる暮らし術 | label only | 190933_Kiku.mp4 · 57.927 |
| ハルテニス(Haru Tennis) | label only | 190933_Kiku.mp4 · 688.548 |
| どうBUZZ | label only | 190933_Kiku.mp4 · 57.927 |
| harukoyanen | label only | 190933_Kiku.mp4 · 585.832 |
| おでんくん景色] | label only | 190933_Kiku.mp4 · 564.891 |
| A.I. Joe | label only | 190933_Kiku.mp4 · 298.285 |
| いいとこドリ | label only | 190933_Kiku.mp4 · 237.595 |
| のんびり暮らしチャンネル | label only | 190933_Kiku.mp4 · 588.852 |
| あさりこオレンジ🍊 | label only | 190933_Kiku.mp4 · 93.922 |
| たっくーTVれいでぃお | label only | 190933_Kiku.mp4 · 74.346 |
| スケボーちゃま | label only | 190933_Kiku.mp4 · 677.321 |
| 価値観の健全化チャンネル | label only | 190933_Kiku.mp4 · 715.269 |
| 長野・小海町ペットと泊まれるペンション | label only | 190933_Kiku.mp4 · 423.275 |
| ジクロエの家 | label only | 190933_Kiku.mp4 · 53.786 |
| YUTO-国際恋愛所 | label only | 190933_Kiku.mp4 · 258.433 |
| ソクラのオモロショート | label only | 190933_Kiku.mp4 · 329.369 |
| おさるのジョージ | label only | 190933_Kiku.mp4 · 301.319 |
| アンドプランツ \| 観葉植物のECサイト | label only | 190933_Kiku.mp4 · 96.998 |
| TBS NEWS DIG PoWered by JNN | label only | 190933_Kiku.mp4 · 607.763 |
| まあじゅ | label only | 190933_Kiku.mp4 · 619.424 |
| 映画雑学チャンネル | label only | 190933_Kiku.mp4 · 666.498 |
| SMILE Channe! | label only | 190933_Kiku.mp4 · 356.472 |
| 生き急ぐOL西園寺 | label only | 190933_Kiku.mp4 · 338.161 |
| RATE VFX | label only | 190933_Kiku.mp4 · 338.662 |
| 素人社長と釣りバカ2人 | label only | 190933_Kiku.mp4 · 289.513 |
| ハリネズミの茶々丸ファミリーー | label only | 190933_Kiku.mp4 · 499.305 |
| まいち🌻ご機嫌ママになる途中 | label only | 190933_Kiku.mp4 · 150.872 |
| 筋肉ランド | label only | 190933_Kiku.mp4 · 591.904 |
| With RIO | label only | 190933_Kiku.mp4 · 585.832 |
| みんみ（子育てママの楽しむ暮らし] | label only | 190933_Kiku.mp4 · 701.716 |
| Chinwe ibekwe | label only | 190933_Kiku.mp4 · 311.639 |
| 大家族藤原さん家Fujiharasanchi | label only | 190933_Kiku.mp4 · 153.468 |
| NOBROCKTV by Nobuyuki Sakuma | label only | 190933_Kiku.mp4 · 557.124 |
| りくらぼ / RikuLab | UCcbY9SXrE46otnOw2gYM3uA | 190933_Kiku.mp4 · 76.924 |
| 髭咲先生の雑学チャンネル | label only | 190933_Kiku.mp4 · 258.433 |
| Sakura Channeru JP. | label only | 190933_Kiku.mp4 · 542.883 |
| シゲチャンネルのガンプラ情報 | label only | 190933_Kiku.mp4 · 588.852 |
| タツヤのお兄さん | label only | 190933_Kiku.mp4 · 37.852 |
| ミシマ. | label only | 190933_Kiku.mp4 · 422.775 |
| やまこう Tech＆Life | label only | 190933_Kiku.mp4 · 121.603 |
| Best EpisodesFanslipn) | label only | 190933_Kiku.mp4 · 489.103 |
| Mamie's Yogini Life -- Wellness Body a Mi... | partial name | 190933_Kiku.mp4 · 535.051 |
| サモハンテレビジョン | label only | 190933_Kiku.mp4 · 690.846 |
| ひらた先生-身体を変えるセルフケア | label only | 190933_Kiku.mp4 · 382.076 |
| ふとえでい-futoedhi | label only | 190933_Kiku.mp4 · 598.933 |
| Lemorele Japan | label only | 190933_Kiku.mp4 · 163.704 |
| ゆうにやん | label only | 190933_Kiku.mp4 · 70.753 |
| mocaち ゃんTime | label only | 190933_Kiku.mp4 · 595.441 |
| 30億円目指す居酒屋社長羽染陽一朗&C0 | label only | 190933_Kiku.mp4 · 368.621 |
| マイコちゃん[IMAIKO] | label only | 190933_Kiku.mp4 · 99.061 |
| バイヤー高橋チャンネル | label only | 190933_Kiku.mp4 · 690.846 |
| SPOLAVA-スポラバ- 体操クラブ | label only | 190933_Kiku.mp4 · 251.094 |
| AOGASHIMA Channe! | label only | 190933_Kiku.mp4 · 595.441 |
| スポーツチャンネル | label only | 190933_Kiku.mp4 · 442.772 |
| 真島ハルの名場面録 | label only | 190933_Kiku.mp4 · 233.5 |
| スタークロニクル | label only | 190933_Kiku.mp4 · 144.2 |
| わこ〻話題アイテムでラク育児ワザ | label only | 190933_Kiku.mp4 · 336.113 |
| 伊勢呂哲也/医師「泌尿器科・消化器内科」 | label only | 190933_Kiku.mp4 · 149.327 |
| 天願家の日常チャンネル笛 | label only | 190933_Kiku.mp4 · 96.483 |
| えびすごはんお家ラ一メン研究. | label only | 190933_Kiku.mp4 · 68.706 |
| お一がすと | label only | 190933_Kiku.mp4 · 704.736 |
| アンジュ・カトリーナ-AngeKatrina- | label only | 190933_Kiku.mp4 · 289.513 |
| DOTホッグ | label only | 190933_Kiku.mp4 · 86.204 |
| 人生暇つぶし日韓生活今日も脱線し.. | partial name | 190933_Kiku.mp4 · 532.468 |
| 大納言あずき | label only | 190933_Kiku.mp4 · 602.046 |
| 鬼妻ちゃんねる(鬱旦那との日常vlog) | label only | 190933_Kiku.mp4 · 607.763 |
| 樹乃～じゅのちゃんねる～ | label only | 190933_Kiku.mp4 · 656.159 |
| サカナクションノート山ロー郎の創作部屋 | label only | 190933_Kiku.mp4 · 238.627 |
| 絶望ライン工 TOKYO FaCtOry Worker | label only | 190933_Kiku.mp4 · 101.106 |
| しずか01100日後に風呂キン界隈卒業する.. | partial name | 190933_Kiku.mp4 · 159.416 |
| kson CLIP | label only | 190933_Kiku.mp4 · 490.118 |
| 囲碁棋士 柳 時のGoChanne! | label only | 190933_Kiku.mp4 · 537.699 |
| ふわゼウス切り抜き（大体不破湊切り抜き] | label only | 190933_Kiku.mp4 · 135.464 |
| 名古屋千種区　整体院健-KEN-(山田健人] | label only | 190933_Kiku.mp4 · 528.447 |
| ドキドキ | label only | 190933_Kiku.mp4 · 342.759 |
| MBS animation 公式チャンネル | label only | 190933_Kiku.mp4 · 714.768 |
| MAI TAKASUG! | label only | 190933_Kiku.mp4 · 98.029 |
| スタディジャンプ(勉強と受験情報1 | label only | 190933_Kiku.mp4 · 438.755 |
| リヨウ | label only | 190933_Kiku.mp4 · 424.277 |
| LabNoZ | label only; low OCR confidence | 190933_Kiku.mp4 · 595.441 |
| みうのデスクと日々！Study&vlog | label only; low OCR confidence | 190933_Kiku.mp4 · 59.989 |
| けんた！今すぐ使えるiPhone活用術 | label only; low OCR confidence | 190933_Kiku.mp4 · 27.572 |
| エアクラHC | label only; low OCR confidence | 190933_Kiku.mp4 · 333.579 |
| あやみるーむ | label only; low OCR confidence | 190933_Kiku.mp4 · 35.29 |
| いいとこ鳥「ぶいすぽ雑学まとめch』 | label only; low OCR confidence | 190933_Kiku.mp4 · 399.134 |
| えぽぽ共和国 | label only; low OCR confidence | 190933_Kiku.mp4 · 682.991 |
| 椿えりこのM男大好きお姉さん | label only; low OCR confidence | 190933_Kiku.mp4 · 118.009 |
| セキログモノとガジェット | label only; low OCR confidence | 190933_Kiku.mp4 · 610.412 |
| お餅スイーツ専門店1今年中にフォロワー1... | partial name; low OCR confidence | 190933_Kiku.mp4 · 142.137 |
| tsujichannel@公式切り抜き | label only; low OCR confidence | 190933_Kiku.mp4 · 709.759 |
| 宝緑園（長崎県のお荼農家] | label only; low OCR confidence | 190933_Kiku.mp4 · 583.266 |
| にじさんじ公式切り抜きチャンネル【NIJIS… | partial name; low OCR confidence | 190933_Kiku.mp4 · 429.505 |
| トレーニングラボ！ノリ | label only; low OCR confidence | 190933_Kiku.mp4 · 364.055 |
| 空から見る世界の闇 | label only; low OCR confidence | 190933_Kiku.mp4 · 376.897 |
| 葉ちゅべ伝説（公式・切り抜き] | label only; low OCR confidence | 190933_Kiku.mp4 · 295.706 |
| 角谷 暢大/AkihiroKakutani | label only; low OCR confidence | 190933_Kiku.mp4 · 576.015 |
| かちょ /Kacho | label only; low OCR confidence | 190933_Kiku.mp4 · 530.465 |
| けーさんとたろー | label only; low OCR confidence | 190933_Kiku.mp4 · 311.139 |
| めざましmedia | label only; low OCR confidence | 190933_Kiku.mp4 · 12.123 |
| ぶりさーもん旅 | label only; low OCR confidence | 190933_Kiku.mp4 · 477.801 |
| nikoや | label only; low OCR confidence | 190933_Kiku.mp4 · 234.515 |
| 1分でほっこりTV | label only; low OCR confidence | 190933_Kiku.mp4 · 621.928 |
| RENIX-株式会社レニクス | label only; low OCR confidence | 190933_Kiku.mp4 · 557.124 |
| 【公式】切抜アカウント テクノブレイク | label only; low OCR confidence | 190933_Kiku.mp4 · 542.883 |
| mimim大田くるみ | label only; low OCR confidence | 190933_Kiku.mp4 · 477.801 |
| k'k'k | label only; low OCR confidence | 190933_Kiku.mp4 · 532.468 |
| I't I botanical_vlog | label only; low OCR confidence | 190933_Kiku.mp4 · 296.223 |
| YASUKOの神意識チヤソネル | label only; low OCR confidence | 190933_Kiku.mp4 · 658.189 |
| 多肉植物つぶつぶ屋 | label only; low OCR confidence | 190933_Kiku.mp4 · 584.783 |
| ペッパピッグPeppaPig-公式チャ... | partial name; low OCR confidence | 190933_Kiku.mp4 · 272.739 |
| どっし一先生(痛みを消す魔法の整体1 | label only; low OCR confidence | 190933_Kiku.mp4 · 580.698 |
| バズ工場 | label only; low OCR confidence | 190933_Kiku.mp4 · 377.398 |
| ジャパン珍光景 | label only; low OCR confidence | 190933_Kiku.mp4 · 387.45 |
| 動物ふレぎ発見 | label only; low OCR confidence | 190933_Kiku.mp4 · 437.237 |
| 伊達千春（美容神』 | UCPgNELa2TvOhmaCIGqJj8zw; low OCR confidence | 190933_Kiku.mp4 · 381.044 |
| 関西フアイトクラブ | label only; low OCR confidence | 190933_Kiku.mp4 · 380.544 |
| ものまね狸Z声真似アフレコ) | label only; low OCR confidence | 190933_Kiku.mp4 · 82.08 |
| ホロライブ推し(切り抜き] | label only; low OCR confidence | 190933_Kiku.mp4 · 234.015 |
| そこら辺にいる猿雑学ch（毎日2... | partial name; low OCR confidence | 190933_Kiku.mp4 · 700.713 |
| しょ ーきち/夫婦の自由な暮らし 〔s_home... | partial name; low OCR confidence | 190933_Kiku.mp4 · 468.601 |
| ホロの伝道師（ホロライブ切り抜き) | label only; low OCR confidence | 190933_Kiku.mp4 · 679.986 |
| テレビ朝日スポーツ（公式 | label only; low OCR confidence | 190933_Kiku.mp4 · 267.094 |
| パパとチマリの部屋「親子のコメディ」 | label only; low OCR confidence | 190933_Kiku.mp4 · 413.479 |
| ReBORN frOm ZERO | label only; low OCR confidence | 190933_Kiku.mp4 · 380.544 |
| ABEMAシヤッフルアイランド | label only; low OCR confidence | 190933_Kiku.mp4 · 404.732 |
| ぜろまるぺッツ | label only; low OCR confidence | 190933_Kiku.mp4 · 661.218 |
| アニメ総集編MADCH | label only; low OCR confidence | 190933_Kiku.mp4 · 364.571 |
| イコラブ関連C | label only; low OCR confidence | 190933_Kiku.mp4 · 140.59 |
| バズキングダム【バズキン】 | label only; low OCR confidence | 190933_Kiku.mp4 · 246.37 |
| バイトな目常 | label only; low OCR confidence | 190933_Kiku.mp4 · 71.785 |
| 筋トレ大学切り抜き（公認] | label only; low OCR confidence | 190933_Kiku.mp4 · 229.355 |
| StevenchannelUEFAチヤンピオンズリー. | label only; low OCR confidence | 190933_Kiku.mp4 · 679.986 |
| つーさんとゆっぴ | label only; low OCR confidence | 190933_Kiku.mp4 · 529.964 |
| JAPANSTREETSTYLE (ヅヤパソストリー.. | partial name; low OCR confidence | 190933_Kiku.mp4 · 689.05 |
| ANPAN KIDS TV ☆ アンパンキッズTV | label only; low OCR confidence | 190933_Kiku.mp4 · 717.287 |
| シヨートスマイル | label only; low OCR confidence | 190933_Kiku.mp4 · 627.421 |
| えすてんけー | label only; low OCR confidence | 190933_Kiku.mp4 · 405.233 |
| いなきゅーch | label only; low OCR confidence | 190933_Kiku.mp4 · 238.111 |
| コダチャンネル/KODAchanne! | label only; low OCR confidence | 190933_Kiku.mp4 · 408.282 |
| Kan ＆ AKi'sCHANNELかんあきチ.. | partial name; low OCR confidence | 190933_Kiku.mp4 · 322.271 |
| 日曜天国傑作選Ch | label only; low OCR confidence | 190933_Kiku.mp4 · 453.702 |
| サッカー指導 | label only; low OCR confidence | 190933_Kiku.mp4 · 413.479 |
| ワクワクショート | label only; low OCR confidence | 190933_Kiku.mp4 · 78.471 |
| カモ井（サポ魂] | label only; low OCR confidence | 190933_Kiku.mp4 · 342.243 |
| 自分で治すTV【はやと先生】 | label only; low OCR confidence | 190933_Kiku.mp4 · 473.153 |
| びじぱとg最強vtuberグループ | label only; low OCR confidence | 190933_Kiku.mp4 · 181.148 |
| KEITO | label only; low OCR confidence | 190933_Kiku.mp4 · 443.273 |
| シャトルの囁き | label only; low OCR confidence | 190933_Kiku.mp4 · 14.17 |
| g退職人サワさん | label only; low OCR confidence | 190933_Kiku.mp4 · 562.501 |
| ゆつペ/GREENVIP-DIYとガヅエット | label only; low OCR confidence | 190933_Kiku.mp4 · 534.551 |
| 蜂なご本店島 | label only; low OCR confidence | 190933_Kiku.mp4 · 380.033 |
| 70cleamキッズ (公式1 | label only; low OCR confidence | 190933_Kiku.mp4 · 635.336 |
| ゴルフレッスン動画Tera-YOu-GOf | label only; low OCR confidence | 190933_Kiku.mp4 · 255.723 |
| マンジャロちゃむ | label only; low OCR confidence | 190933_Kiku.mp4 · 645.771 |
| メイズ.[MeiZl.] | label only; low OCR confidence | 190933_Kiku.mp4 · 549.454 |
| KENTO〔マジシャソ先生] | label only; low OCR confidence | 190933_Kiku.mp4 · 186.434 |
| お一ちゃんと。（ワーママ〕 | label only; low OCR confidence | 190933_Kiku.mp4 · 218.631 |
| 妻筋TUbe | label only; low OCR confidence | 190933_Kiku.mp4 · 350.859 |
| くいるく | label only; low OCR confidence | 190933_Kiku.mp4 · 297.77 |
| らいく1不器用アラサー初めてのDIN日記 | label only; low OCR confidence | 190933_Kiku.mp4 · 276.804 |
| ヘえマシ? | label only; low OCR confidence | 190933_Kiku.mp4 · 438.238 |
| いよぴ | label only; low OCR confidence | 190933_Kiku.mp4 · 602.546 |
| ぴちゃん2人暮らしのvlog | label only; low OCR confidence | 190933_Kiku.mp4 · 468.1 |
| VSPO!フタク | label only; low OCR confidence | 190933_Kiku.mp4 · 722.005 |
| TKyUkOChAnV [キューコちゃん... | partial name; low OCR confidence | 190933_Kiku.mp4 · 717.287 |
| YU(ボイトレ難民集合] | label only; low OCR confidence | 190933_Kiku.mp4 · 495.705 |
| Anime - [osHl No kol  official Channe! | label only; low OCR confidence | 190933_Kiku.mp4 · 543.399 |
| ショート情報 | label only; low OCR confidence | 190933_Kiku.mp4 · 499.805 |
| メイズ.[MeizI.] | label only; low OCR confidence | 190933_Kiku.mp4 · 550.455 |
| とだ「ンジユを切り抜くもの] | label only; low OCR confidence | 190933_Kiku.mp4 · 709.258 |
| だいじろーDar0 | label only; low OCR confidence | 190933_Kiku.mp4 · 126.776 |
| れな@恋愛 | label only; low OCR confidence | 190933_Kiku.mp4 · 313.657 |
| てぃーちゃんねる👑 | label only; low OCR confidence | 190933_Kiku.mp4 · 499.805 |
| 鉄ビジョンCh | label only; low OCR confidence | 190933_Kiku.mp4 · 539.863 |
| 柔術たまに釣り〜EnjoyBjjLife〜 | label only; low OCR confidence | 190933_Kiku.mp4 · 649.423 |
| みんち」#乙世代の味方] | label only; low OCR confidence | 190933_Kiku.mp4 · 247.917 |
| X凍子ママ | label only; low OCR confidence | 190933_Kiku.mp4 · 347.84 |
| 世界の唱き | label only; low OCR confidence | 190933_Kiku.mp4 · 658.696 |
| Lý Hải | label only; low OCR confidence | 190933_Kiku.mp4 · 613.934 |
| 蜂なご本店🇺🇸 | label only; low OCR confidence | 190933_Kiku.mp4 · 378.415 |
| える / Elu【にじさんじ】 | label only; low OCR confidence | 190933_Kiku.mp4 · 551.472 |
| サカナクションクリップ1山口一郎mel.. | partial name; low OCR confidence | 190933_Kiku.mp4 · 630.959 |
| わっぴー | label only; low OCR confidence | 190933_Kiku.mp4 · 429.505 |
| 比ノ咲死亡 | label only; low OCR confidence; uncertain glyphs | 190933_Kiku.mp4 · 312.139 |
| yui☆ | label only; low OCR confidence | 190933_Kiku.mp4 · 155.531 |
| 车世界 | label only; low OCR confidence | 190933_Kiku.mp4 · 66.144 |
| とも先生【数学勉強法】 | label only | 191425_Kiku.mp4 · 60 |
