//
//  ImmersionTests.swift
//  JojoTests
//
//  Bring-your-own-video pipeline: link parsing, timing modes, job decoding,
//  recognition scoring and vocab key mapping.
//

import Foundation
import Testing
@testable import Jojo

@MainActor
struct ImmersionTests {

    // MARK: YouTube links

    @Test(arguments: [
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://youtube.com/watch?v=dQw4w9WgXcQ&t=42s", "dQw4w9WgXcQ"),
        ("https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://youtu.be/dQw4w9WgXcQ?si=abc", "dQw4w9WgXcQ"),
        ("youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/live/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("  dQw4w9WgXcQ  ", "dQw4w9WgXcQ"),
    ])
    func youTubeLinkParsesVideoId(input: String, expected: String) {
        #expect(YouTubeLink.videoId(from: input) == expected)
    }

    @Test(arguments: [
        "",
        "hello",
        "https://vimeo.com/123456789",
        "https://www.youtube.com/watch?v=short",
        "https://www.youtube.com/channel/UC1234567890",
        "https://evil-youtube.com/watch?v=dQw4w9WgXcQ",
        "dQw4w9WgXc!",
    ])
    func youTubeLinkRejectsOtherInput(input: String) {
        #expect(YouTubeLink.videoId(from: input) == nil)
    }

    // MARK: Timing modes

    @Test func lineTimingDecodesAndDisablesWordHighlight() throws {
        let json = """
        {"tokens":[{"surface":"こんにちは","romaji":"konnichiwa","start":1,"end":3,"pos":"expression"}],
         "translation":"Hello","start":1,"end":3,"timing":"line"}
        """
        let line = try JSONDecoder().decode(Line.self, from: Data(json.utf8))
        #expect(line.timing == "line")
        #expect(line.hasWordTiming == false)
    }

    @Test func missingTimingUsesValidLegacyTokenTimes() throws {
        let json = """
        {"tokens":[{"surface":"はい","romaji":"hai","pos":"expression","start":0,"end":1}],"translation":"Yes","start":0,"end":1}
        """
        let line = try JSONDecoder().decode(Line.self, from: Data(json.utf8))
        #expect(line.timing == nil)
        #expect(line.hasWordTiming)
    }

    @Test func tokenIndexFollowsWordsOnlyWhenWordTimed() {
        let tokens = [
            Token(surface: "今日", reading: "きょう", romaji: "kyou", start: 0.0, end: 0.6, pos: "noun"),
            Token(surface: "は", romaji: "wa", start: 0.6, end: 0.9, pos: "particle"),
            Token(surface: "晴れ", reading: "はれ", romaji: "hare", start: 0.9, end: 1.6, pos: "noun"),
        ]
        let wordClip = makeClip(lines: [Line(tokens: tokens, translation: "Sunny today", start: 0, end: 1.6)])
        #expect(PlaybackUI.tokenIndex(clip: wordClip, line: 0, time: 0.3) == 0)
        #expect(PlaybackUI.tokenIndex(clip: wordClip, line: 0, time: 1.2) == 2)

        let lineClip = makeClip(lines: [Line(tokens: tokens, translation: "Sunny today", start: 0, end: 1.6, timing: "line")])
        #expect(PlaybackUI.tokenIndex(clip: lineClip, line: 0, time: 0.3) == nil)
        #expect(PlaybackUI.tokenIndex(clip: lineClip, line: 0, time: 1.2) == nil)
    }

    @Test func wordCursorStopsDuringRealPausesInsteadOfHoldingThePreviousWord() {
        let tokens = [
            Token(surface: "今日", romaji: "kyou", start: 0, end: 0.5, pos: "noun"),
            Token(surface: "です", romaji: "desu", start: 1, end: 1.5, pos: "auxiliary"),
        ]
        let clip = makeClip(lines: [Line(tokens: tokens, translation: "Today.", start: 0, end: 1.6, timing: "word")])
        #expect(PlaybackUI.tokenIndex(clip: clip, line: 0, time: 0.3) == 0)
        #expect(PlaybackUI.tokenIndex(clip: clip, line: 0, time: 0.7) == nil)
        #expect(PlaybackUI.tokenIndex(clip: clip, line: 0, time: 1.2) == 1)
        #expect(PlaybackUI.tokenIndex(clip: clip, line: 0, time: 1.55) == nil)
    }

    @Test func silentProlongedMarksDoNotDisableOtherwiseValidWordTiming() {
        let tokens = [
            Token(surface: "はい", romaji: "hai", start: 0, end: 0.8, pos: "expression"),
            Token(surface: "ー", romaji: "", start: 0.8, end: 0.8, pos: "unknown"),
        ]
        let line = Line(tokens: tokens, translation: "Yes.", start: 0, end: 1, timing: "word")
        #expect(line.hasWordTiming)
        #expect(tokens[1].isPunctuation)
    }

    @Test func invalidTokenTimingFallsBackToSentenceSync() {
        let tokens = [
            Token(surface: "あ", romaji: "a", start: 0.0, end: 0.5, pos: "interjection"),
            Token(surface: "ね", romaji: "ne", start: 0.5, end: 0.5, pos: "particle"),
        ]
        let clip = makeClip(lines: [Line(tokens: tokens, translation: "Ah", start: 0, end: 1)])
        #expect(!clip.lines[0].hasWordTiming)
        #expect(PlaybackUI.tokenIndex(clip: clip, line: 0, time: 0.7) == nil)
    }

    @Test func punctuationAliasesDoNotDisableWordKaraoke() {
        let tokens = [
            Token(surface: "どうした", romaji: "doushita", start: 0.4, end: 1.15, pos: "verb"),
            Token(surface: "の", romaji: "no", start: 1.15, end: 1.45, pos: "particle"),
            Token(surface: "？", romaji: "", start: 1.45, end: 1.45, pos: "punct"),
        ]
        let line = Line(tokens: tokens, translation: "What's wrong?", start: 0.4, end: 1.6, timing: "word")
        #expect(tokens[2].isPunctuation)
        #expect(line.hasWordTiming)
        #expect(PlaybackUI.tokenIndex(clip: makeClip(lines: [line]), line: 0, time: 1.2) == 1)
    }

    @Test func repeatedSentenceWindowsAreNotWordAlignment() {
        let tokens = [
            Token(surface: "今日", romaji: "kyou", start: 0, end: 2, pos: "noun"),
            Token(surface: "です", romaji: "desu", start: 0, end: 2, pos: "auxiliary"),
        ]
        let line = Line(tokens: tokens, translation: "Today.", start: 0, end: 2, timing: "word")
        #expect(!line.hasWordTiming)
        let clip = makeClip(lines: [line])
        #expect(PlaybackUI.tokenIndex(clip: clip, line: 0, time: 1) == nil)
    }

    @Test func emptyAndOutOfBoundsTokenTimesDoNotClaimWordSync() {
        #expect(!Line(tokens: [], translation: "", start: 0, end: 1).hasWordTiming)
        let token = Token(surface: "はい", romaji: "hai", start: 3, end: 4, pos: "expression")
        #expect(!Line(tokens: [token], translation: "Yes", start: 0, end: 1, timing: "word").hasWordTiming)
    }

    // MARK: Job decoding

    @Test func jobDecodesEmbeddedClipAndReportsReady() throws {
        let json = """
        {"id":"0f9c1c7e-1111-4222-8333-944445555666","video_id":"dQw4w9WgXcQ","status":"succeeded",
         "stage":"done","attempts":1,"max_attempts":3,"error_code":null,"error_message":null,
         "title":"駅で道を聞く","channel_name":"Tokyo Walks","video_duration_sec":312,
         "clip_id":"immersion-dQw4w9WgXcQ","timing_mode":"mixed",
         "clips":{"id":"immersion-dQw4w9WgXcQ","video_id":"dQw4w9WgXcQ","title":"駅で道を聞く",
           "channel_name":"Tokyo Walks","category":"interview","difficulty":"beginner","duration_sec":312,
           "published":false,
           "lines":[{"tokens":[{"surface":"すみません","romaji":"sumimasen","start":4.2,"end":5.0,"pos":"expression"}],
                     "translation":"Excuse me","start":4.2,"end":5.0,"timing":"word"}]}}
        """
        let job = try JSONDecoder().decode(ImmersionJob.self, from: Data(json.utf8))
        #expect(job.phase == .ready)
        #expect(job.clip?.id == "immersion-dQw4w9WgXcQ")
        #expect(job.clip?.lines.first?.hasWordTiming == true)
        #expect(job.displayTitle == "駅で道を聞く")
        #expect(job.stageProgress == 1)

        // The device cache round-trips the decoded clip.
        let cached = try JSONDecoder().decode(ImmersionJob.self, from: JSONEncoder().encode(job))
        #expect(cached.clip?.id == job.clip?.id)
        #expect(cached.phase == .ready)
    }

    @Test func succeededWithoutClipIsStillWorking() throws {
        let json = """
        {"id":"a","video_id":"dQw4w9WgXcQ","status":"succeeded","stage":"publishing","clips":null}
        """
        let job = try JSONDecoder().decode(ImmersionJob.self, from: Data(json.utf8))
        #expect(job.phase == .working)
        #expect(job.isActive)
    }

    @Test func unprocessableJobsOnlyRetryWhenTheVideoCanChange() throws {
        func job(_ code: String) throws -> ImmersionJob {
            let json = """
            {"id":"a","video_id":"dQw4w9WgXcQ","status":"unprocessable","stage":"checking","error_code":"\(code)"}
            """
            return try JSONDecoder().decode(ImmersionJob.self, from: Data(json.utf8))
        }
        #expect(try job("private_video").canRetry)
        #expect(try job("no_japanese_dialogue").canRetry == false)
        #expect(try job("too_short").canRetry == false)
    }

    // MARK: Recognition similarity

    @Test func identicalLineScoresFull() {
        #expect(SpeechScoring.score(heard: "ありがとうございます", target: "ありがとうございます。") == 100)
    }

    @Test func partialLineDoesNotScoreFull() {
        let score = SpeechScoring.score(heard: "ありがとう", target: "ありがとうございます")
        #expect(score > 0)
        #expect(score < 100)
    }

    @Test func unrelatedSpeechScoresLow() {
        #expect(SpeechScoring.similarity("さようなら", "いただきます") < 40)
        #expect(SpeechScoring.similarity("", "いただきます") == 0)
    }

    @Test func similarityIsSymmetric() {
        #expect(SpeechScoring.similarity("たべます", "たべません") == SpeechScoring.similarity("たべません", "たべます"))
    }

    // MARK: Vocab mapping

    @Test func vocabKeySplitsIntoTermAndReading() {
        let pair = VocabSync.split("食べる|たべる")
        #expect(pair?.0 == "食べる")
        #expect(pair?.1 == "たべる")
        let kana = VocabSync.split("は|")
        #expect(kana?.0 == "は")
        #expect(kana?.1 == "")
        #expect(VocabSync.split("|たべる") == nil)
        #expect(VocabSync.split("nobar") == nil)
    }

    // MARK: Helpers

    private func makeClip(lines: [Line]) -> Clip {
        ClipRow(
            id: "test-clip", videoId: "dQw4w9WgXcQ", title: "Test", channelName: "Jojo", category: nil,
            difficulty: nil, sourceStartSec: 0, durationSec: 10, lines: lines, published: false,
            channelAvatarColor: nil, thumbnailGradient: nil
        ).clip
    }
}
