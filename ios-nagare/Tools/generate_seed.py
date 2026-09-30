#!/usr/bin/env python3
"""
Generates the bundled seed content for Nagare:
  Nagare/Resources/SeedClips.json   (14 fully tokenized clips)
  Nagare/Resources/Dictionary.json  (~300 common N5-N3 words, keyed by surface)
  Nagare/Resources/SeedVocab.json   (36 pre-saved words with clip context)

Edit the data below and re-run:  python3 Tools/generate_seed.py
Every token surface used in a clip line MUST exist in DICT (the script asserts this).

REAL VIDEO SWAP-IN: each clip has "videoId": "PLACEHOLDER_...". Replace it with a real
11-character YouTube ID and adjust "duration" + per-line timings ("times") to match the video.
The app switches to the YouTube IFrame player automatically for real IDs.
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Nagare", "Resources")

# surface: (reading, romaji, pos, jlpt, [defs], extras)
# extras: conj (godan/ichidan/irregular), form (plain/polite/keigo/casual),
#         alt [alt readings], base (surface, reading, romaji)
DICT = {}

def W(surface, reading, romaji, pos, jlpt, defs, conj=None, form=None, alt=None, base=None):
    DICT[surface] = dict(reading=reading, romaji=romaji, pos=pos, jlpt=jlpt, defs=defs,
                         conj=conj, form=form, alt=alt or [], base=base)

# ---------- Particles & auxiliaries ----------
W("は", "", "wa", "particle", "N5", ["topic marker", "as for …"])
W("が", "", "ga", "particle", "N5", ["subject marker", "but; however"])
W("を", "", "o", "particle", "N5", ["direct object marker"])
W("に", "", "ni", "particle", "N5", ["to; toward (destination)", "at; in; on (time or place)", "for; in order to"])
W("で", "", "de", "particle", "N5", ["at; in (place of action)", "by; with (means)"])
W("の", "", "no", "particle", "N5", ["'s; of (possessive)", "one (nominalizer)"])
W("も", "", "mo", "particle", "N5", ["also; too", "even"])
W("と", "", "to", "particle", "N5", ["and; with", "quotation marker ('that …')"])
W("ね", "", "ne", "particle", "N5", ["right?; isn't it?", "softens a statement"])
W("よ", "", "yo", "particle", "N5", ["you know; I tell you (emphasis)"])
W("か", "", "ka", "particle", "N5", ["question marker"])
W("ぞ", "", "zo", "particle", "N3", ["emphatic sentence ending (masculine)"], form="casual")
W("けど", "", "kedo", "particle", "N4", ["but; although"], form="casual")
W("て", "", "te", "particle", "N5", ["te-form connector: and; and then"])
W("こそ", "", "koso", "particle", "N3", ["precisely; for sure (strong emphasis)"])
W("です", "", "desu", "copula", "N5", ["to be (polite copula)"], form="polite")
W("だ", "", "da", "copula", "N5", ["to be (plain copula)"], form="plain")
W("でし", "", "deshi", "copula", "N5", ["was; were (polite past stem of です)"], form="polite", base=("です", "", "desu"))
W("でしょ", "", "desho", "auxiliary", "N4", ["right?; surely (seeking agreement)", "probably"], form="casual")
W("ます", "", "masu", "auxiliary", "N5", ["polite verb ending"], form="polite")
W("まし", "", "mashi", "auxiliary", "N5", ["polite past stem (→ ました)"], form="polite", base=("ます", "", "masu"))
W("ましょう", "", "mashou", "auxiliary", "N5", ["let's …; shall we … (polite volitional)"], form="polite")
W("た", "", "ta", "auxiliary", "N5", ["past tense marker", "completion"])
W("ない", "", "nai", "auxiliary", "N5", ["not (negative ending)"], form="plain")
W("なかっ", "", "naka", "auxiliary", "N5", ["didn't (past negative stem)"], base=("ない", "", "nai"))
W("たい", "", "tai", "auxiliary", "N5", ["want to …"])
W("う", "", "u", "auxiliary", "N4", ["let's …; I'll … (volitional)"], form="casual")
W("ん", "", "n", "auxiliary", "N4", ["explanatory の (it's that …)"], form="casual")
W("な", "", "na", "auxiliary", "N5", ["connects na-adjectives to nouns"])
W("すぎる", "", "sugiru", "auxiliary", "N4", ["too …; excessively"], conj="ichidan")
W("とって", "", "totte", "expression", "N3", ["for; to (as in 'for me'), used as にとって"])
W("ため", "", "tame", "noun", "N4", ["for the sake of; in order to", "because of"])
W("よう", "", "you", "noun", "N4", ["so that; to the point that", "way; manner"])
W("中", "じゅう", "juu", "suffix", "N4", ["throughout; all through"], alt=["なか", "ちゅう"])

# ---------- Clip vocabulary ----------
W("今日", "きょう", "kyou", "noun", "N5", ["today", "these days"], alt=["こんにち"])
W("天気", "てんき", "tenki", "noun", "N5", ["weather; the elements", "fair weather"])
W("いい", "", "ii", "i-adjective", "N5", ["good; nice", "okay; fine"])
W("コーヒー", "", "koohii", "noun", "N5", ["coffee"])
W("二つ", "ふたつ", "futatsu", "noun", "N5", ["two (things)"])
W("ください", "", "kudasai", "expression", "N5", ["please (give me)", "please do …"], form="polite")
W("ここ", "", "koko", "pronoun", "N5", ["here; this place"])
W("ケーキ", "", "keeki", "noun", "N5", ["cake"])
W("本当", "ほんとう", "hontou", "noun", "N5", ["truth; reality", "really (with に)"])
W("美味しい", "おいしい", "oishii", "i-adjective", "N5", ["delicious; tasty"])
W("いらっしゃいませ", "", "irasshaimase", "expression", "N4", ["welcome (to the store)"], form="keigo")
W("コンビニ", "", "konbini", "noun", "N4", ["convenience store"])
W("おにぎり", "", "onigiri", "noun", "N4", ["rice ball"])
W("食べ", "たべ", "tabe", "verb", "N5", ["to eat", "to live on; to make a living"], conj="ichidan", base=("食べる", "たべる", "taberu"))
W("温め", "あたため", "atatame", "verb", "N3", ["to warm up; to heat"], conj="ichidan", base=("温める", "あたためる", "atatameru"))
W("はい", "", "hai", "interjection", "N5", ["yes", "here (roll call)"])
W("お願い", "おねがい", "onegai", "noun", "N5", ["request; favor", "please (お願いします)"], form="polite")
W("し", "", "shi", "verb", "N5", ["to do (stem of する)", "to make"], conj="irregular", base=("する", "", "suru"))
W("え", "", "e", "interjection", "N5", ["eh?; what?"], form="casual")
W("嘘", "うそ", "uso", "noun", "N4", ["lie; falsehood", "no way!; really?!"])
W("俺", "おれ", "ore", "pronoun", "N4", ["I; me (casual, masculine)"], form="casual")
W("絶対", "ぜったい", "zettai", "adverb", "N3", ["absolutely; definitely", "never (with negative)"])
W("諦め", "あきらめ", "akirame", "verb", "N3", ["to give up; to abandon"], conj="ichidan", base=("諦める", "あきらめる", "akirameru"))
W("みんな", "", "minna", "noun", "N5", ["everyone; everybody"])
W("守る", "まもる", "mamoru", "verb", "N4", ["to protect; to defend", "to keep (a promise)"], conj="godan")
W("強く", "つよく", "tsuyoku", "i-adjective", "N5", ["strongly; powerfully (adverbial form of 強い)"], base=("強い", "つよい", "tsuyoi"))
W("なり", "", "nari", "verb", "N5", ["to become (stem of なる)"], conj="godan", base=("なる", "", "naru"))
W("何", "なに", "nani", "pronoun", "N5", ["what", "how many (with counters)"], alt=["なん"])
W("これ", "", "kore", "pronoun", "N5", ["this (thing)"])
W("可愛い", "かわいい", "kawaii", "i-adjective", "N5", ["cute; adorable", "lovely"])
W("この", "", "kono", "pronoun", "N5", ["this (…)"])
W("猫", "ねこ", "neko", "noun", "N5", ["cat"])
W("私", "わたし", "watashi", "pronoun", "N5", ["I; me"])
W("友達", "ともだち", "tomodachi", "noun", "N5", ["friend"])
W("一緒", "いっしょ", "issho", "noun", "N5", ["together (with に)", "the same"])
W("遊ぼ", "あそぼ", "asobo", "verb", "N5", ["to play (volitional stem of 遊ぶ)"], conj="godan", base=("遊ぶ", "あそぶ", "asobu"))
W("めっちゃ", "", "meccha", "adverb", "N3", ["super; really (Kansai slang)"], form="casual")
W("スープ", "", "suupu", "noun", "N5", ["soup"])
W("濃く", "こく", "koku", "i-adjective", "N3", ["richly; thickly (form of 濃い)"], base=("濃い", "こい", "koi"))
W("最高", "さいこう", "saikou", "na-adjective", "N3", ["the best; supreme", "awesome"])
W("次", "つぎ", "tsugi", "noun", "N5", ["next", "following"])
W("どこ", "", "doko", "pronoun", "N5", ["where"])
W("行き", "いき", "iki", "verb", "N5", ["to go (stem of 行く)"], conj="godan", base=("行く", "いく", "iku"))
W("正解", "せいかい", "seikai", "noun", "N3", ["correct answer", "the right choice"])
W("なんと", "", "nanto", "adverb", "N3", ["believe it or not; what …!"])
W("東京", "とうきょう", "toukyou", "noun", "N5", ["Tokyo"])
W("タワー", "", "tawaa", "noun", "N4", ["tower"])
W("全然", "ぜんぜん", "zenzen", "adverb", "N4", ["(not) at all", "totally (casual)"])
W("分から", "わから", "wakara", "verb", "N5", ["to understand (negative stem of 分かる)"], conj="godan", base=("分かる", "わかる", "wakaru"))
W("悔しい", "くやしい", "kuyashii", "i-adjective", "N3", ["frustrating; vexing", "regrettable"])
W("勝ち", "かち", "kachi", "verb", "N4", ["to win (stem of 勝つ)"], conj="godan", base=("勝つ", "かつ", "katsu"))
W("こんばんは", "", "konbanwa", "expression", "N5", ["good evening"])
W("来", "き", "ki", "verb", "N5", ["to come (stem of 来る)"], conj="irregular", base=("来る", "くる", "kuru"))
W("くれ", "", "kure", "verb", "N4", ["to do for me (stem of くれる)", "to give (to me)"], conj="ichidan", base=("くれる", "", "kureru"))
W("ありがとう", "", "arigatou", "expression", "N5", ["thank you"], form="casual")
W("コメント", "", "komento", "noun", "N4", ["comment"])
W("読み", "よみ", "yomi", "verb", "N5", ["to read (stem of 読む)"], conj="godan", base=("読む", "よむ", "yomu"))
W("実は", "じつは", "jitsu wa", "adverb", "N4", ["actually; to tell the truth"])
W("昨日", "きのう", "kinou", "noun", "N5", ["yesterday"], alt=["さくじつ"])
W("寝", "ね", "ne", "verb", "N5", ["to sleep (stem of 寝る)"], conj="ichidan", base=("寝る", "ねる", "neru"))
W("眠い", "ねむい", "nemui", "i-adjective", "N4", ["sleepy; drowsy"])
W("頑張り", "がんばり", "ganbari", "verb", "N4", ["to do one's best (stem of 頑張る)"], conj="godan", base=("頑張る", "がんばる", "ganbaru"))
W("明日", "あした", "ashita", "noun", "N5", ["tomorrow"], alt=["あす"])
W("配信", "はいしん", "haishin", "noun", "N3", ["(live) stream; broadcast", "distribution"])
W("楽しみ", "たのしみ", "tanoshimi", "noun", "N4", ["looking forward to", "pleasure; enjoyment"])
W("すみません", "", "sumimasen", "expression", "N5", ["excuse me", "I'm sorry"], form="polite")
W("ちょっと", "", "chotto", "adverb", "N5", ["a little; a bit", "just a moment"])
W("好き", "すき", "suki", "na-adjective", "N5", ["liked; favorite", "to like"])
W("食べ物", "たべもの", "tabemono", "noun", "N5", ["food"])
W("寿司", "すし", "sushi", "noun", "N4", ["sushi"])
W("一番", "いちばん", "ichiban", "adverb", "N5", ["most; best", "number one"])
W("あなた", "", "anata", "pronoun", "N5", ["you"])
W("大切", "たいせつ", "taisetsu", "na-adjective", "N4", ["important; precious", "cherished"])
W("言葉", "ことば", "kotoba", "noun", "N5", ["word; language", "speech; expression"])
W("母", "はは", "haha", "noun", "N5", ["(my) mother"])
W("言っ", "いっ", "it", "verb", "N5", ["to say (stem of 言う)"], conj="godan", base=("言う", "いう", "iu"))
W("大丈夫", "だいじょうぶ", "daijoubu", "na-adjective", "N5", ["okay; all right", "safe; no problem"])
W("いう", "", "iu", "verb", "N5", ["called; named (という)", "to say"], conj="godan")
W("辛い", "つらい", "tsurai", "i-adjective", "N3", ["painful; hard; tough"], alt=["からい"])
W("時", "とき", "toki", "noun", "N5", ["time; moment", "when …"])
W("いつも", "", "itsumo", "adverb", "N5", ["always; usually"])
W("思い出し", "おもいだし", "omoidashi", "verb", "N4", ["to remember; to recall (stem of 思い出す)"], conj="godan", base=("思い出す", "おもいだす", "omoidasu"))
W("おはよう", "", "ohayou", "expression", "N5", ["good morning"], form="casual")
W("公園", "こうえん", "kouen", "noun", "N5", ["park"])
W("行こ", "いこ", "iko", "verb", "N5", ["to go (volitional stem of 行く)"], conj="godan", base=("行く", "いく", "iku"))
W("りんご", "", "ringo", "noun", "N5", ["apple"])
W("一つ", "ひとつ", "hitotsu", "noun", "N5", ["one (thing)"])
W("どうぞ", "", "douzo", "adverb", "N5", ["please; here you are", "go ahead"], form="polite")
W("一", "いち", "ichi", "noun", "N5", ["one"])
W("二", "に", "ni", "noun", "N5", ["two"])
W("三", "さん", "san", "noun", "N5", ["three"])
W("空", "そら", "sora", "noun", "N5", ["sky"], alt=["から"])
W("青い", "あおい", "aoi", "i-adjective", "N5", ["blue", "green (traffic light)", "inexperienced"])
W("やばい", "", "yabai", "i-adjective", "N3", ["dangerous; uh-oh", "amazing (slang)"], form="casual")
W("ボス", "", "bosu", "noun", "N3", ["boss"])
W("強", "つよ", "tsuyo", "i-adjective", "N5", ["strong (stem of 強い)"], base=("強い", "つよい", "tsuyoi"))
W("もう", "", "mou", "adverb", "N5", ["already; anymore", "another; more"])
W("一回", "いっかい", "ikkai", "noun", "N5", ["once; one time"])
W("やろ", "", "yaro", "verb", "N4", ["to do (volitional stem of やる)"], conj="godan", form="casual", base=("やる", "", "yaru"))
W("よし", "", "yoshi", "interjection", "N3", ["all right!; yes!"], form="casual")
W("勝っ", "かっ", "kat", "verb", "N4", ["to win (stem of 勝つ)"], conj="godan", base=("勝つ", "かつ", "katsu"))
W("ジャンプ", "", "janpu", "noun", "N4", ["jump"])
W("タイミング", "", "taimingu", "noun", "N3", ["timing"])
W("難しい", "むずかしい", "muzukashii", "i-adjective", "N5", ["difficult; hard"])
W("一日", "いちにち", "ichinichi", "noun", "N5", ["one day; all day", "first day of the month (ついたち)"], alt=["ついたち"])
W("練習", "れんしゅう", "renshuu", "noun", "N5", ["practice; training"])
W("やっと", "", "yatto", "adverb", "N4", ["finally; at last"])
W("できる", "", "dekiru", "verb", "N5", ["to be able to; can", "to be completed"], conj="ichidan")
W("皆さん", "みなさん", "minasan", "noun", "N5", ["everyone (polite)"], form="polite")
W("ぜひ", "", "zehi", "adverb", "N4", ["by all means; definitely"])
W("挑戦", "ちょうせん", "chousen", "noun", "N3", ["challenge; attempt"])
W("み", "", "mi", "verb", "N5", ["try doing (stem of みる)"], conj="ichidan", base=("みる", "", "miru"))

# ---------- Extra common words (dictionary only) ----------
EXTRA = [
 ("水","みず","mizu","noun","N5","water"),("お茶","おちゃ","ocha","noun","N5","tea; green tea"),
 ("ご飯","ごはん","gohan","noun","N5","cooked rice; meal"),("朝","あさ","asa","noun","N5","morning"),
 ("夜","よる","yoru","noun","N5","night; evening"),("昼","ひる","hiru","noun","N5","noon; daytime"),
 ("人","ひと","hito","noun","N5","person; people"),("子供","こども","kodomo","noun","N5","child"),
 ("男","おとこ","otoko","noun","N5","man; male"),("女","おんな","onna","noun","N5","woman; female"),
 ("先生","せんせい","sensei","noun","N5","teacher; doctor"),("学生","がくせい","gakusei","noun","N5","student"),
 ("学校","がっこう","gakkou","noun","N5","school"),("会社","かいしゃ","kaisha","noun","N5","company"),
 ("家","いえ","ie","noun","N5","house; home"),("部屋","へや","heya","noun","N5","room"),
 ("駅","えき","eki","noun","N5","station"),("電車","でんしゃ","densha","noun","N5","train"),
 ("車","くるま","kuruma","noun","N5","car"),("道","みち","michi","noun","N5","road; way"),
 ("店","みせ","mise","noun","N5","shop; store"),("町","まち","machi","noun","N5","town"),
 ("国","くに","kuni","noun","N5","country"),("日本","にほん","nihon","noun","N5","Japan"),
 ("日本語","にほんご","nihongo","noun","N5","Japanese (language)"),("英語","えいご","eigo","noun","N5","English (language)"),
 ("本","ほん","hon","noun","N5","book"),("映画","えいが","eiga","noun","N5","movie"),
 ("音楽","おんがく","ongaku","noun","N5","music"),("歌","うた","uta","noun","N5","song"),
 ("写真","しゃしん","shashin","noun","N5","photograph"),("電話","でんわ","denwa","noun","N5","telephone"),
 ("時間","じかん","jikan","noun","N5","time; hours"),("今","いま","ima","noun","N5","now"),
 ("毎日","まいにち","mainichi","noun","N5","every day"),("週末","しゅうまつ","shuumatsu","noun","N4","weekend"),
 ("雨","あめ","ame","noun","N5","rain"),("雪","ゆき","yuki","noun","N5","snow"),
 ("花","はな","hana","noun","N5","flower"),("山","やま","yama","noun","N5","mountain"),
 ("海","うみ","umi","noun","N5","sea; ocean"),("川","かわ","kawa","noun","N5","river"),
 ("犬","いぬ","inu","noun","N5","dog"),("鳥","とり","tori","noun","N5","bird"),
 ("魚","さかな","sakana","noun","N5","fish"),("肉","にく","niku","noun","N5","meat"),
 ("野菜","やさい","yasai","noun","N5","vegetable"),("卵","たまご","tamago","noun","N5","egg"),
 ("お金","おかね","okane","noun","N5","money"),("仕事","しごと","shigoto","noun","N5","work; job"),
 ("名前","なまえ","namae","noun","N5","name"),("友人","ゆうじん","yuujin","noun","N4","friend (formal)"),
 ("家族","かぞく","kazoku","noun","N5","family"),("父","ちち","chichi","noun","N5","(my) father"),
 ("兄","あに","ani","noun","N5","(my) older brother"),("姉","あね","ane","noun","N5","(my) older sister"),
 ("弟","おとうと","otouto","noun","N5","younger brother"),("妹","いもうと","imouto","noun","N5","younger sister"),
 ("旅行","りょこう","ryokou","noun","N5","trip; travel"),("料理","りょうり","ryouri","noun","N5","cooking; cuisine"),
 ("質問","しつもん","shitsumon","noun","N5","question"),("答え","こたえ","kotae","noun","N4","answer"),
 ("気持ち","きもち","kimochi","noun","N4","feeling; mood"),("心","こころ","kokoro","noun","N4","heart; mind"),
 ("夢","ゆめ","yume","noun","N4","dream"),("世界","せかい","sekai","noun","N4","world"),
 ("声","こえ","koe","noun","N5","voice"),("顔","かお","kao","noun","N5","face"),
 ("目","め","me","noun","N5","eye"),("手","て","te","noun","N5","hand"),
 ("足","あし","ashi","noun","N5","foot; leg"),("頭","あたま","atama","noun","N5","head"),
 ("元気","げんき","genki","na-adjective","N5","healthy; energetic"),("静か","しずか","shizuka","na-adjective","N5","quiet"),
 ("有名","ゆうめい","yuumei","na-adjective","N5","famous"),("便利","べんり","benri","na-adjective","N5","convenient"),
 ("簡単","かんたん","kantan","na-adjective","N4","easy; simple"),("大変","たいへん","taihen","na-adjective","N5","tough; terrible; very"),
 ("嫌い","きらい","kirai","na-adjective","N5","disliked"),("上手","じょうず","jouzu","na-adjective","N5","skillful; good at"),
 ("下手","へた","heta","na-adjective","N5","unskillful; bad at"),("暇","ひま","hima","na-adjective","N5","free time; not busy"),
 ("綺麗","きれい","kirei","na-adjective","N5","pretty; clean"),("特別","とくべつ","tokubetsu","na-adjective","N4","special"),
 ("大きい","おおきい","ookii","i-adjective","N5","big"),("小さい","ちいさい","chiisai","i-adjective","N5","small"),
 ("新しい","あたらしい","atarashii","i-adjective","N5","new"),("古い","ふるい","furui","i-adjective","N5","old (things)"),
 ("高い","たかい","takai","i-adjective","N5","tall; expensive"),("安い","やすい","yasui","i-adjective","N5","cheap"),
 ("暑い","あつい","atsui","i-adjective","N5","hot (weather)"),("寒い","さむい","samui","i-adjective","N5","cold (weather)"),
 ("楽しい","たのしい","tanoshii","i-adjective","N5","fun; enjoyable"),("面白い","おもしろい","omoshiroi","i-adjective","N5","interesting; funny"),
 ("早い","はやい","hayai","i-adjective","N5","early; fast"),("遅い","おそい","osoi","i-adjective","N5","late; slow"),
 ("忙しい","いそがしい","isogashii","i-adjective","N5","busy"),("嬉しい","うれしい","ureshii","i-adjective","N4","happy; glad"),
 ("悲しい","かなしい","kanashii","i-adjective","N4","sad"),("怖い","こわい","kowai","i-adjective","N4","scary"),
 ("優しい","やさしい","yasashii","i-adjective","N4","kind; gentle"),("恥ずかしい","はずかしい","hazukashii","i-adjective","N4","embarrassing"),
 ("凄い","すごい","sugoi","i-adjective","N4","amazing; terrific"),("すごい","","sugoi","i-adjective","N4","amazing; terrific"),
 ("甘い","あまい","amai","i-adjective","N5","sweet"),("熱い","あつい","atsui","i-adjective","N5","hot (to the touch)"),
 ("強い","つよい","tsuyoi","i-adjective","N5","strong"),("弱い","よわい","yowai","i-adjective","N5","weak"),
 ("濃い","こい","koi","i-adjective","N3","rich; thick; dark (color)"),("多い","おおい","ooi","i-adjective","N5","many; a lot"),
 ("少ない","すくない","sukunai","i-adjective","N5","few; little"),("近い","ちかい","chikai","i-adjective","N5","near"),
 ("遠い","とおい","tooi","i-adjective","N5","far"),("悪い","わるい","warui","i-adjective","N5","bad"),
 ("食べる","たべる","taberu","verb","N5","to eat"),("飲む","のむ","nomu","verb","N5","to drink"),
 ("見る","みる","miru","verb","N5","to see; to watch"),("聞く","きく","kiku","verb","N5","to hear; to listen; to ask"),
 ("話す","はなす","hanasu","verb","N5","to speak; to talk"),("読む","よむ","yomu","verb","N5","to read"),
 ("書く","かく","kaku","verb","N5","to write"),("行く","いく","iku","verb","N5","to go"),
 ("来る","くる","kuru","verb","N5","to come"),("帰る","かえる","kaeru","verb","N5","to return home"),
 ("する","","suru","verb","N5","to do"),("やる","","yaru","verb","N4","to do (casual)"),
 ("なる","","naru","verb","N5","to become"),("ある","","aru","verb","N5","to exist (inanimate); to have"),
 ("いる","","iru","verb","N5","to be; to exist (animate)"),("寝る","ねる","neru","verb","N5","to sleep"),
 ("起きる","おきる","okiru","verb","N5","to wake up"),("遊ぶ","あそぶ","asobu","verb","N5","to play"),
 ("買う","かう","kau","verb","N5","to buy"),("売る","うる","uru","verb","N5","to sell"),
 ("待つ","まつ","matsu","verb","N5","to wait"),("持つ","もつ","motsu","verb","N5","to hold; to have"),
 ("使う","つかう","tsukau","verb","N5","to use"),("作る","つくる","tsukuru","verb","N5","to make"),
 ("分かる","わかる","wakaru","verb","N5","to understand"),("知る","しる","shiru","verb","N5","to know"),
 ("思う","おもう","omou","verb","N4","to think"),("言う","いう","iu","verb","N5","to say"),
 ("勝つ","かつ","katsu","verb","N4","to win"),("負ける","まける","makeru","verb","N4","to lose"),
 ("頑張る","がんばる","ganbaru","verb","N4","to do one's best"),("守る","まもる","mamoru","verb","N4","to protect"),
 ("諦める","あきらめる","akirameru","verb","N3","to give up"),("温める","あたためる","atatameru","verb","N3","to warm up"),
 ("思い出す","おもいだす","omoidasu","verb","N4","to remember; to recall"),("くれる","","kureru","verb","N4","to give (to me)"),
 ("歩く","あるく","aruku","verb","N5","to walk"),("走る","はしる","hashiru","verb","N5","to run"),
 ("泳ぐ","およぐ","oyogu","verb","N5","to swim"),("歌う","うたう","utau","verb","N5","to sing"),
 ("会う","あう","au","verb","N5","to meet"),("始める","はじめる","hajimeru","verb","N4","to begin"),
 ("終わる","おわる","owaru","verb","N4","to end; to finish"),("入る","はいる","hairu","verb","N5","to enter"),
 ("出る","でる","deru","verb","N5","to leave; to appear"),("住む","すむ","sumu","verb","N5","to live (reside)"),
 ("働く","はたらく","hataraku","verb","N5","to work"),("休む","やすむ","yasumu","verb","N5","to rest"),
 ("教える","おしえる","oshieru","verb","N5","to teach; to tell"),("習う","ならう","narau","verb","N5","to learn"),
 ("覚える","おぼえる","oboeru","verb","N5","to memorize; to remember"),("忘れる","わすれる","wasureru","verb","N5","to forget"),
 ("好む","このむ","konomu","verb","N3","to prefer"),("笑う","わらう","warau","verb","N4","to laugh; to smile"),
 ("泣く","なく","naku","verb","N4","to cry"),("死ぬ","しぬ","shinu","verb","N5","to die"),
 ("生きる","いきる","ikiru","verb","N4","to live; to exist"),("見せる","みせる","miseru","verb","N5","to show"),
 ("とても","","totemo","adverb","N5","very"),("たくさん","","takusan","adverb","N5","a lot; many"),
 ("少し","すこし","sukoshi","adverb","N5","a little"),("すぐ","","sugu","adverb","N5","immediately; soon"),
 ("また","","mata","adverb","N5","again; also"),("まだ","","mada","adverb","N5","still; not yet"),
 ("よく","","yoku","adverb","N5","often; well"),("ゆっくり","","yukkuri","adverb","N5","slowly; leisurely"),
 ("本当に","ほんとうに","hontou ni","adverb","N5","really; truly"),("多分","たぶん","tabun","adverb","N5","probably; maybe"),
 ("一緒に","いっしょに","issho ni","adverb","N5","together"),("そう","","sou","adverb","N5","so; like that"),
 ("どう","","dou","adverb","N5","how"),("なぜ","","naze","adverb","N5","why"),
 ("誰","だれ","dare","pronoun","N5","who"),("いつ","","itsu","pronoun","N5","when"),
 ("それ","","sore","pronoun","N5","that (near you)"),("あれ","","are","pronoun","N5","that (over there)"),
 ("そこ","","soko","pronoun","N5","there"),("あそこ","","asoko","pronoun","N5","over there"),
 ("彼","かれ","kare","pronoun","N4","he; boyfriend"),("彼女","かのじょ","kanojo","pronoun","N4","she; girlfriend"),
 ("僕","ぼく","boku","pronoun","N5","I (casual, masculine)"),("自分","じぶん","jibun","pronoun","N4","oneself"),
 ("こんにちは","","konnichiwa","expression","N5","hello; good afternoon"),("さようなら","","sayounara","expression","N5","goodbye"),
 ("おやすみ","","oyasumi","expression","N5","good night"),("ごめんなさい","","gomennasai","expression","N5","I'm sorry"),
 ("いただきます","","itadakimasu","expression","N5","thanks for the food (before eating)"),("ごちそうさま","","gochisousama","expression","N5","thanks for the meal (after eating)"),
 ("お疲れ様","おつかれさま","otsukaresama","expression","N4","thanks for your hard work"),("よろしく","","yoroshiku","expression","N5","nice to meet you; please treat me well"),
 ("大好き","だいすき","daisuki","na-adjective","N5","love; really like"),("残念","ざんねん","zannen","na-adjective","N4","unfortunate; too bad"),
 ("本気","ほんき","honki","noun","N3","seriousness; for real"),("勉強","べんきょう","benkyou","noun","N5","study"),
 ("試合","しあい","shiai","noun","N4","match; game"),("ゲーム","","geemu","noun","N5","game"),
 ("アニメ","","anime","noun","N5","anime"),("番組","ばんぐみ","bangumi","noun","N4","TV program"),
 ("動画","どうが","douga","noun","N3","video"),("字幕","じまく","jimaku","noun","N3","subtitles"),
 ("意味","いみ","imi","noun","N4","meaning"),("漢字","かんじ","kanji","noun","N5","kanji; Chinese characters"),
 ("春","はる","haru","noun","N5","spring"),("夏","なつ","natsu","noun","N5","summer"),
 ("秋","あき","aki","noun","N5","autumn"),("冬","ふゆ","fuyu","noun","N5","winter"),
 ("月","つき","tsuki","noun","N5","moon; month"),("星","ほし","hoshi","noun","N5","star"),
 ("火","ひ","hi","noun","N5","fire"),("風","かぜ","kaze","noun","N5","wind"),
 ("病気","びょうき","byouki","noun","N5","illness"),("薬","くすり","kusuri","noun","N5","medicine"),
 ("病院","びょういん","byouin","noun","N5","hospital"),("先輩","せんぱい","senpai","noun","N3","senior (at school or work)"),
 ("約束","やくそく","yakusoku","noun","N4","promise"),("準備","じゅんび","junbi","noun","N4","preparation"),
 ("最後","さいご","saigo","noun","N4","last; end"),("最初","さいしょ","saisho","noun","N4","first; beginning"),
 ("場所","ばしょ","basho","noun","N4","place; location"),("空港","くうこう","kuukou","noun","N4","airport"),
 ("切符","きっぷ","kippu","noun","N5","ticket"),("地図","ちず","chizu","noun","N5","map"),
 ("右","みぎ","migi","noun","N5","right"),("左","ひだり","hidari","noun","N5","left"),
 ("上","うえ","ue","noun","N5","above; up"),("下","した","shita","noun","N5","below; down"),
 ("前","まえ","mae","noun","N5","front; before"),("後ろ","うしろ","ushiro","noun","N5","behind"),
]
for s, r, ro, pos, j, d in EXTRA:
    if s not in DICT:
        conj = None
        if pos == "verb":
            if s in ("する",):
                conj = "irregular"
            elif s in ("来る",):
                conj = "irregular"
            elif s.endswith("る") and ro[-3:-2] in ("e", "i") and s not in ("帰る", "入る", "走る", "知る", "作る", "売る", "終わる", "やる", "なる", "ある", "守る", "頑張る", "分かる"):
                conj = "ichidan"
            else:
                conj = "godan"
        DICT[s] = dict(reading=r, romaji=ro, pos=pos, jlpt=j, defs=[x.strip() for x in d.split(";")] if pos != "expression" else [d],
                       conj=conj, form=None, alt=[], base=None)

PUNCT = {"、", "。", "!", "?", "「", "」", "…"}

# ---------- Clips ----------
# Each line: "surface|surface|…" ; use "何@なん" to pick a specific reading for that token.
CLIPS = [
 dict(id="kissa-stories-01", videoId="PLACEHOLDER_kissa01", title="Rainy Afternoon at the Kissaten", channel="Kissa Stories",
      avatar="#C9803F", category="drama", difficulty="Beginner", duration=24, gradient=["#3B2414", "#8A4B22", "#E3A35B"],
      lines=[("今日|は|天気|が|いい|です|ね", "The weather's nice today, isn't it?"),
             ("コーヒー|を|二つ|ください", "Two coffees, please."),
             ("ここ|の|ケーキ|は|本当|に|美味しい|です|よ", "The cake here is really delicious, you know.")]),
 dict(id="konbini-diaries-01", videoId="PLACEHOLDER_konbini01", title="Late Night Onigiri Run", channel="Konbini Diaries",
      avatar="#E0463A", category="drama", difficulty="Beginner", duration=24, gradient=["#0E1A2B", "#1F3F5C", "#E0463A"],
      lines=[("いらっしゃいませ", "Welcome!"),
             ("コンビニ|で|おにぎり|を|食べ|まし|た|。", "I ate an onigiri at the konbini."),
             ("温め|ます|か", "Would you like it heated up?"),
             ("はい|、|お願い|し|ます", "Yes, please.")]),
 dict(id="hoshizora-academy-07", videoId="PLACEHOLDER_hoshizora07", title="The Promise on the Rooftop", channel="Hoshizora Anime Club",
      avatar="#4B6BFF", category="anime", difficulty="Intermediate", duration=22, gradient=["#0B1030", "#2B2F7A", "#F29E4C"],
      lines=[("え|?|嘘|でしょ|!", "What? No way!"),
             ("俺|は|絶対|に|諦め|ない|ぞ", "I'm never giving up!"),
             ("みんな|を|守る|ため|に|強く|なり|たい", "I want to get stronger to protect everyone.")]),
 dict(id="neko-cafe-02", videoId="PLACEHOLDER_nekocafe02", title="A New Friend at the Neko Café", channel="Mochi Animation",
      avatar="#F4A6C0", category="anime", difficulty="Beginner", duration=18, gradient=["#2A1B2E", "#7A3E6B", "#F7C6A3"],
      lines=[("何|これ|、|可愛い|!", "What's this? So cute!"),
             ("この|猫|は|私|の|友達|だ|よ", "This cat is my friend."),
             ("一緒|に|遊ぼ|う", "Let's play together.")]),
 dict(id="ramen-road-trip-03", videoId="PLACEHOLDER_ramen03", title="Tonkotsu in Fukuoka", channel="Tabi Tabi TV",
      avatar="#F2B134", category="variety", difficulty="Intermediate", duration=28, gradient=["#2B1405", "#9C3D10", "#F2B134"],
      lines=[("これ|は|めっちゃ|美味しい|です|ね|!", "This is seriously delicious!"),
             ("スープ|が|濃く|て|最高|です", "The broth is so rich, it's the best."),
             ("次|は|どこ|に|行き|ましょう|か", "Where shall we go next?")]),
 dict(id="quiz-showdown-11", videoId="PLACEHOLDER_quiz11", title="Final Round: Landmarks", channel="Waiwai Variety",
      avatar="#22C1C3", category="variety", difficulty="Advanced", duration=30, gradient=["#06212B", "#0E6E78", "#FDBB2D"],
      lines=[("正解|は|なんと|東京|タワー|でし|た|!", "And the correct answer is… Tokyo Tower!"),
             ("全然|分から|なかっ|た|です", "I had no idea at all."),
             ("悔しい|けど|次|こそ|勝ち|ます", "It stings, but next time I'll win for sure.")]),
 dict(id="kitsune-yuki-stream-01", videoId="PLACEHOLDER_yuki01", title="Evening Stream Opening", channel="Kitsune Yuki Ch.",
      avatar="#FF8FAB", category="vtuber", difficulty="Beginner", duration=22, gradient=["#1B0F2E", "#5B2A86", "#FF8FAB"],
      lines=[("みんな|、|こんばんは|!", "Good evening, everyone!"),
             ("今日|も|来|て|くれ|て|ありがとう", "Thanks for coming again today."),
             ("コメント|を|読み|ます|ね", "I'll read your comments.")]),
 dict(id="tsukimi-rin-zatsudan-05", videoId="PLACEHOLDER_rin05", title="Late-Night Zatsudan", channel="Tsukimi Rin Ch.",
      avatar="#8EC5FC", category="vtuber", difficulty="Intermediate", duration=32, gradient=["#050B1F", "#1D2B64", "#8EC5FC"],
      lines=[("実は|昨日|、|全然|寝|て|ない|ん|です", "Actually, I barely slept at all last night."),
             ("眠い|けど|頑張り|ます", "I'm sleepy, but I'll do my best."),
             ("明日|の|配信|も|楽しみ|に|し|て|て|ね", "Look forward to tomorrow's stream too!")]),
 dict(id="harajuku-street-02", videoId="PLACEHOLDER_harajuku02", title="What's Your Favorite Food?", channel="Machi no Koe",
      avatar="#34C759", category="interview", difficulty="Beginner", duration=26, gradient=["#10261A", "#2E7D4F", "#F6E27F"],
      lines=[("すみません|、|ちょっと|いい|です|か", "Excuse me, do you have a moment?"),
             ("好き|な|食べ物|は|何@なん|です|か", "What's your favorite food?"),
             ("寿司|が|一番|好き|です", "I like sushi the most.")]),
 dict(id="words-that-matter-04", videoId="PLACEHOLDER_words04", title="Words That Matter", channel="Machi no Koe",
      avatar="#34C759", category="interview", difficulty="Advanced", duration=36, gradient=["#1C1917", "#57402F", "#D6B48A"],
      lines=[("あなた|に|とって|大切|な|言葉|は|何@なん|です|か", "What words are important to you?"),
             ("母|が|言っ|た|「|大丈夫|」|と|いう|言葉|です", "The word 'daijoubu' that my mother used to say."),
             ("辛い|時|に|いつも|思い出し|ます", "I always remember it when times are hard.")]),
 dict(id="piyo-picnic-01", videoId="PLACEHOLDER_piyo01", title="Piyo's Picnic", channel="Hiyoko Kids",
      avatar="#FFD23F", category="kids", difficulty="Beginner", duration=22, gradient=["#1E3A5F", "#3FA7D6", "#FFD23F"],
      lines=[("おはよう|!", "Good morning!"),
             ("今日|は|公園|に|行こ|う", "Let's go to the park today."),
             ("りんご|を|一つ|どうぞ", "Here, have an apple."),
             ("ありがとう|!|美味しい|ね", "Thank you! It's yummy!")]),
 dict(id="counting-kuma-03", videoId="PLACEHOLDER_kuma03", title="Counting with Kuma", channel="Hiyoko Kids",
      avatar="#FFD23F", category="kids", difficulty="Beginner", duration=18, gradient=["#12355B", "#4E9F3D", "#FFE66D"],
      lines=[("一|、|二|、|三|!", "One, two, three!"),
             ("空|が|青い|ね", "The sky is so blue."),
             ("明日|も|一緒|に|遊ぼ|う|ね", "Let's play together tomorrow too!")]),
 dict(id="boss-rush-live-09", videoId="PLACEHOLDER_boss09", title="Boss Rush: Attempt #37", channel="GameNama",
      avatar="#A3E635", category="gaming", difficulty="Intermediate", duration=24, gradient=["#0A0F0A", "#1F4D2B", "#A3E635"],
      lines=[("やばい|、|ボス|が|強|すぎる|!", "Oh no, this boss is way too strong!"),
             ("もう|一回|やろ|う", "Let's go one more time."),
             ("よし|、|勝っ|た|!", "Yes! I won!")]),
 dict(id="speedrun-commentary-02", videoId="PLACEHOLDER_speedrun02", title="The Frame-Perfect Jump", channel="GameNama",
      avatar="#A3E635", category="gaming", difficulty="Advanced", duration=34, gradient=["#0B0B14", "#3A1C71", "#FF6B00"],
      lines=[("この|ジャンプ|は|タイミング|が|難しい|ん|です|よ", "The timing on this jump is really tricky."),
             ("一日|中|練習|し|て|やっと|できる|よう|に|なり|まし|た", "I practiced all day and finally got it down."),
             ("皆さん|も|ぜひ|挑戦|し|て|み|て|ください", "Everyone, you should definitely give it a try too.")]),
]

def weight(s):
    return 0.35 if s in PUNCT else max(1.0, len(s))

def build_clip(c):
    n = len(c["lines"])
    dur = float(c["duration"])
    lead, tail = 1.0, 1.2
    avail = dur - lead - tail
    wts = [sum(weight(t.split("@")[0]) for t in l[0].split("|")) + 3 for l in c["lines"]]
    total = sum(wts)
    t = lead
    lines = []
    for (text, tr), w in zip(c["lines"], wts):
        seg = avail * w / total
        speak = seg * 0.78
        start, end = round(t, 2), round(t + speak, 2)
        toks = []
        parts = text.split("|")
        pw = sum(weight(p.split("@")[0]) for p in parts)
        cur = start
        for p in parts:
            surf, _, forced = p.partition("@")
            d = (end - start) * weight(surf) / pw
            ts, te = round(cur, 2), round(cur + d, 2)
            cur += d
            if surf in PUNCT:
                toks.append(dict(surface=surf, altReadings=[], romaji="", start=ts, end=te, pos="punctuation",
                                 definitions=[], tappable=False))
                continue
            assert surf in DICT, f"missing dictionary entry: {surf} (clip {c['id']})"
            e = DICT[surf]
            readings = [e["reading"]] + e["alt"] if e["reading"] else []
            if forced:
                assert forced in readings, f"{surf}@{forced}"
                readings = [forced] + [r for r in readings if r != forced]
            romaji = e["romaji"]
            if forced == "なん" and surf == "何":
                romaji = "nan"
            tok = dict(surface=surf, reading=readings[0] if readings else None, altReadings=readings[1:],
                       romaji=romaji, start=ts, end=te, pos=e["pos"], conjugationClass=e["conj"], jlpt=e["jlpt"],
                       definitions=e["defs"], formality=e["form"], tappable=True)
            if e["base"]:
                tok["baseForm"], br, tok["baseRomaji"] = e["base"]
                tok["baseReading"] = br or None
            toks.append({k: v for k, v in tok.items() if v is not None})
        lines.append(dict(tokens=toks, translation=tr, start=start, end=end))
        t += seg
    return dict(id=c["id"], videoId=c["videoId"], title=c["title"], channelName=c["channel"],
                channelAvatarColor=c["avatar"], category=c["category"], difficulty=c["difficulty"],
                durationSec=dur, lines=lines, thumbnailGradient=c["gradient"])

clips = [build_clip(c) for c in CLIPS]

# ---------- Dictionary output ----------
dictionary = {}
for s, e in DICT.items():
    readings = [e["reading"]] + e["alt"] if e["reading"] else []
    entry = dict(surface=s, readings=readings, romaji=e["romaji"], pos=e["pos"], jlpt=e["jlpt"], definitions=e["defs"])
    if e["conj"]: entry["conjugationClass"] = e["conj"]
    if e["form"]: entry["formality"] = e["form"]
    if e["base"]:
        entry["baseForm"], br, entry["baseRomaji"] = e["base"]
        if br: entry["baseReading"] = br
    dictionary[s] = entry

# ---------- Seed vocab (36 words) ----------
SEED = [  # (clip id, token surface, occurrences, state, stepIndex, dueOffsetHours)
 ("kissa-stories-01", "天気", 3, "learning", 2, -2), ("konbini-diaries-01", "食べ", 12, "known", 6, 400),
 ("words-that-matter-04", "言葉", 5, "learning", 3, -1), ("words-that-matter-04", "大丈夫", 4, "learning", 2, -3),
 ("piyo-picnic-01", "行こ", 7, "known", 6, 300), ("neko-cafe-02", "可愛い", 6, "learning", 4, 20),
 ("kissa-stories-01", "美味しい", 9, "known", 6, 500), ("kissa-stories-01", "今日", 14, "known", 6, 600),
 ("konbini-diaries-01", "おにぎり", 2, "learning", 1, -1), ("konbini-diaries-01", "温め", 1, "new", 0, -1),
 ("hoshizora-academy-07", "嘘", 3, "learning", 2, -4), ("hoshizora-academy-07", "絶対", 2, "learning", 1, -2),
 ("hoshizora-academy-07", "諦め", 1, "new", 0, -1), ("hoshizora-academy-07", "守る", 2, "learning", 2, 6),
 ("neko-cafe-02", "猫", 5, "known", 6, 450), ("neko-cafe-02", "友達", 4, "learning", 4, 30),
 ("ramen-road-trip-03", "めっちゃ", 3, "learning", 3, -1), ("ramen-road-trip-03", "最高", 4, "learning", 3, 10),
 ("ramen-road-trip-03", "濃く", 1, "new", 0, -1), ("quiz-showdown-11", "正解", 2, "learning", 2, -5),
 ("quiz-showdown-11", "全然", 6, "learning", 4, 40), ("quiz-showdown-11", "悔しい", 1, "new", 0, -1),
 ("kitsune-yuki-stream-01", "こんばんは", 5, "known", 6, 350), ("kitsune-yuki-stream-01", "コメント", 2, "learning", 2, -1),
 ("tsukimi-rin-zatsudan-05", "眠い", 2, "learning", 2, -2), ("tsukimi-rin-zatsudan-05", "配信", 3, "learning", 3, 12),
 ("tsukimi-rin-zatsudan-05", "楽しみ", 1, "new", 0, -1), ("harajuku-street-02", "食べ物", 3, "learning", 2, -3),
 ("harajuku-street-02", "一番", 4, "known", 6, 420), ("words-that-matter-04", "大切", 2, "learning", 1, -1),
 ("words-that-matter-04", "辛い", 1, "new", 0, -1), ("words-that-matter-04", "思い出し", 1, "new", 0, -1),
 ("counting-kuma-03", "空", 3, "learning", 3, 16), ("boss-rush-live-09", "やばい", 8, "known", 6, 380),
 ("speedrun-commentary-02", "難しい", 3, "learning", 2, -1), ("speedrun-commentary-02", "練習", 2, "new", 0, -1),
]
assert len(SEED) == 36
clip_by_id = {c["id"]: c for c in clips}
seed_vocab = []
for i, (cid, surf, occ, state, step, due) in enumerate(SEED):
    c = clip_by_id[cid]
    found = None
    for li, line in enumerate(c["lines"]):
        for tok in line["tokens"]:
            if tok["surface"] == surf:
                found = (li, line, tok); break
        if found: break
    assert found, f"{surf} not in {cid}"
    li, line, tok = found
    sentence = "".join(t["surface"] for t in line["tokens"])
    seed_vocab.append(dict(clipId=cid, lineIndex=li, surface=surf, contextSentence=sentence,
                           occurrenceCount=occ, srsState=state, intervalStepIndex=step,
                           dueOffsetHours=due, addedDaysAgo=(36 - i) // 3))

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "SeedClips.json"), "w", encoding="utf-8") as f:
    json.dump(clips, f, ensure_ascii=False, separators=(",", ":"))
with open(os.path.join(OUT, "Dictionary.json"), "w", encoding="utf-8") as f:
    json.dump(dictionary, f, ensure_ascii=False, separators=(",", ":"))
with open(os.path.join(OUT, "SeedVocab.json"), "w", encoding="utf-8") as f:
    json.dump(seed_vocab, f, ensure_ascii=False, separators=(",", ":"))
print(f"clips={len(clips)} dictionary={len(dictionary)} seedVocab={len(seed_vocab)}")
for c in clips:
    print(c["id"], c["durationSec"], [ (l["start"], l["end"]) for l in c["lines"]])
