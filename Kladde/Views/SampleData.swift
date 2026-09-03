//
//  SampleData.swift
//  Kladde
//
//  Preview fixtures: sample entries and texts covering the different
//  pipeline states. The app itself launches from persisted entries.
//
//  The dictated text is German because transcription is pinned to German —
//  an English fixture would show a pipeline the app never runs. The interface
//  strings around it stay English.
//
// The fixtures hold verbatim sample transcripts. Rewrapping one would change
// the text a preview renders.
// swiftlint:disable line_length

import Foundation

extension DictationEntry {
    // MARK: - Sample entries

    static let samples: [DictationEntry] = [
        DictationEntry(
            title: "Feedback zum Onboarding",
            createdAt: .now.addingTimeInterval(-40 * 60),
            duration: 58,
            status: .complete,
            transcript: "Okay, also, ähm, ich bin gerade nochmal durch das neue Onboarding gegangen und ich finde immer noch, der zweite Schritt macht viel zu viel. Also wir fragen da Benachrichtigungen ab und Analytics und das ganze Konto-Setup, alles auf einmal. Äh, das sollten wir wahrscheinlich in einzelne Schritte aufteilen. Und der Willkommenstext ist — der ist viel zu lang, das liest doch keiner. Vielleicht einfach auf einen Satz runterkürzen. Ach, und die kleinen Fortschrittspunkte unten, äh, die würde ich etwas dezenter machen.",
            cleanedUp: """
                Der zweite Onboarding-Schritt macht zu viel und sollte aufgeteilt werden: Er fragt Benachrichtigungen, Analytics und das gesamte Konto-Setup auf einmal ab.

                Zwei kleinere Punkte aus demselben Durchgang:

                - Der Willkommenstext ist deutlich zu lang. Ihn liest niemand, also auf einen Satz kürzen.
                - Die Fortschrittspunkte am unteren Rand sollten dezenter werden.
                """,
            waveformSeed: 3,
            waveform: (0..<80).map { index in
                let x = Double(index)
                return Float(0.15 + 0.85 * abs(sin(x * 0.23 + 1.7) * sin(x * 0.71)))
            }
        ),
        DictationEntry(
            title: "Offsite-Termine für Priya",
            createdAt: .now.addingTimeInterval(-3 * 3_600),
            duration: 84,
            status: .complete,
            transcript: "Hey, also, für die Mail an Priya — ähm, wegen dem Offsite. Die letzte September-Woche geht nicht mehr, weil, äh, das halbe Plattform-Team im Urlaub ist. Deswegen würde ich stattdessen den vierzehnten bis sechzehnten Oktober vorschlagen. Die Location in, ähm, in Hamburg ist die Woche wohl noch frei, Lena hat nachgefragt. Äh, frag sie mal, ob das Budget aus dem dritten Quartal übertragen wird, und, ach ja, erwähn noch, dass wir die endgültige Teilnehmerzahl bis Mitte September brauchen … äh, nee, warte, bis Ende September, weil die Location die Zahlen zwei Wochen vorher haben will.",
            cleanedUp: "Zur Mail an Priya wegen des Offsites: Die letzte September-Woche geht nicht mehr, weil das halbe Plattform-Team im Urlaub ist. Ich schlage stattdessen den 14. bis 16. Oktober vor. Lena hat nachgefragt — die Location in Hamburg ist in dieser Woche noch frei. Frag Priya, ob das Budget aus dem dritten Quartal übertragen wird, und erwähne, dass wir die endgültige Teilnehmerzahl bis Ende September brauchen, weil die Location die Zahlen zwei Wochen im Voraus will.",
            waveformSeed: 11
        ),
        DictationEntry(
            title: "Standup-Notizen",
            createdAt: .now.addingTimeInterval(-26 * 3_600),
            duration: 41,
            status: .complete,
            transcript: "Äh, Standup. Gestern habe ich das Migrationsskript fertig gemacht und, ähm, die Staging-Datenbank wieder synchron bekommen. Heute pair ich mit Tomás am Export-Bug, und, äh, wenn Zeit bleibt, fange ich mit der Retry-Logik an. Blocker … ähm, ich warte immer noch auf den Zugang zum Analytics-Dashboard, ich hab IT jetzt zweimal angeschrieben.",
            cleanedUp: """
                ## Gestern

                - Migrationsskript fertiggestellt
                - Staging-Datenbank wieder synchronisiert

                ## Heute

                - Mit Tomás am Export-Bug pairen
                - Mit der Retry-Logik anfangen, falls Zeit bleibt

                ## Blocker

                - Zugang zum Analytics-Dashboard fehlt weiterhin, IT zweimal angeschrieben
                """,
            waveformSeed: 8
        ),
        DictationEntry(
            title: "Idee: Vorlage für den Wochenrückblick",
            createdAt: .now.addingTimeInterval(-31 * 3_600),
            duration: 67,
            status: .complete,
            transcript: "Also, spontane Idee, ähm, für die Sache mit dem Wochenrückblick. Was wäre, wenn die Vorlage einfach drei Abschnitte hätte, also, äh, was etwas gebracht hat, was gebremst hat, und was ich sein lasse. Weil im Moment schreibe ich diese langen, ähm, diese langen Tagebucheinträge und lese die nie wieder. Maximal drei Stichpunkte pro Abschnitt. Und vielleicht, äh, vielleicht noch eine einzelne Zeile oben drüber, so als Überschrift für die Woche. Das war's, so einfach wie möglich halten.",
            cleanedUp: """
                Die Vorlage für den Wochenrückblick soll nur drei Abschnitte haben:

                1. Was etwas gebracht hat
                2. Was gebremst hat
                3. Was ich sein lasse

                Höchstens drei Stichpunkte je Abschnitt, dazu oben eine einzelne Zeile als Überschrift für die Woche. Bisher schreibe ich lange Tagebucheinträge, die ich nie wieder lese.
                """,
            waveformSeed: 14
        ),
        DictationEntry(
            title: "Gedanken nach der Design-Kritik",
            createdAt: .now.addingTimeInterval(-96 * 3_600),
            duration: 133,
            status: .complete,
            transcript: "Okay, Gedanken-Dump nach der Kritik. Ähm, das Feedback zu den leeren Zuständen war fair, die wirken wirklich wie nachträglich drangeklebt. Ich glaube, das, äh, das größere Problem ist aber, dass wir drei verschiedene Kartenstile auf einem Screen haben und, ähm, niemand konnte mir sagen, warum. Also entweder vereinheitlichen wir die, oder wir, na ja, wir schreiben auf, wann welcher gilt. Äh, Mareks Punkt mit den Icon-Gewichten war auch gut, die Toolbar mischt gefüllte und ungefüllte Icons und das sieht unruhig aus, wenn man's einmal gesehen hat. Ähm, was noch … ach ja, Animationen. Alle waren sich einig, dass die Übergänge abrupt wirken, also, äh, vielleicht Standarddauern und eine Easing-Kurve, einmal festgelegt, und alles nutzt die. Ich schreibe einen Vorschlag, ähm, vor der nächsten Kritik.",
            cleanedUp: "Notizen nach der Design-Kritik: Das Feedback zu den leeren Zuständen war fair — sie wirken tatsächlich nachträglich angefügt. Das größere Problem ist, dass wir drei verschiedene Kartenstile auf einem Screen haben und niemand begründen konnte, warum. Wir sollten sie entweder vereinheitlichen oder festhalten, wann welcher gilt. Auch Mareks Punkt zu den Icon-Gewichten war gut: Die Toolbar mischt gefüllte und ungefüllte Icons, was unruhig wirkt, sobald man es bemerkt. Bei den Animationen waren sich alle einig, dass die Übergänge abrupt wirken — wir sollten Standarddauern und eine einzelne Easing-Kurve festlegen und überall verwenden. Ich schreibe vor der nächsten Kritik einen Vorschlag.",
            waveformSeed: 21
        ),
        DictationEntry(
            title: "Fragen an die Steuerberaterin",
            createdAt: .now.addingTimeInterval(-12 * 86_400),
            duration: 49,
            status: .complete,
            transcript: "Ähm, vor dem Termin am Donnerstag. Nach der, äh, nach der Homeoffice-Pauschale fragen, ob die neuen Regeln schon fürs letzte Jahr gelten. Und, ähm, ob wir auf vierteljährliche Vorauszahlungen umstellen sollten, weil die Nachzahlung dieses Jahr, äh, ziemlich heftig war. Ach, und die Sache mit der Abschreibung für den Laptop ansprechen.",
            cleanedUp: "Fragen für den Termin am Donnerstag: Gelten die neuen Regeln zur Homeoffice-Pauschale bereits für das letzte Jahr? Sollten wir auf vierteljährliche Vorauszahlungen umstellen, nachdem die Nachzahlung dieses Jahr sehr hoch ausfiel? Außerdem die Abschreibung für den Laptop ansprechen.",
            waveformSeed: 17
        ),
        DictationEntry(
            title: "Checkliste für die Fahrradwerkstatt",
            createdAt: .now.addingTimeInterval(-45 * 86_400),
            duration: 33,
            status: .complete,
            transcript: "Äh, kurze Liste für die Fahrradwerkstatt. Die, ähm, die hintere Bremse quietscht, wahrscheinlich die Beläge. Die Schaltung springt im, äh, im dritten und vierten Gang. Und das Licht, das Vorderlicht flackert, wenn es kalt ist. Fragen, was eine große Inspektion kostet, vielleicht lohnt es sich, na ja, alles auf einmal machen zu lassen.",
            cleanedUp: "Liste für die Fahrradwerkstatt: Die hintere Bremse quietscht, wahrscheinlich liegt es an den Belägen. Die Schaltung springt zwischen dem dritten und vierten Gang, und das Vorderlicht flackert bei Kälte. Nachfragen, was eine große Inspektion kostet — womöglich lohnt es sich, alles auf einmal machen zu lassen.",
            waveformSeed: 26
        )
    ]

    // MARK: - Preview fixture texts

    static let demoTranscript = "Ähm, okay, Notiz an mich selbst. Daran denken, Alex den aktualisierten Vertrag vor Freitag zu schicken, das hat Priorität. Und, äh, ich habe die Flüge für die Berlin-Reise immer noch nicht gebucht, am besten morgen früh, wenn die Preise zurückgesetzt werden oder so. Ach, und Dana fragen, was aus der, ähm, aus der November-Rechnung geworden ist, die steht immer noch offen."

    // MARK: - Preview fixtures

    static var previewRecording: DictationEntry {
        DictationEntry(
            title: "New Dictation",
            createdAt: .now.addingTimeInterval(-23),
            duration: nil,
            status: .recording,
            waveformSeed: 5
        )
    }

    static var previewTranscribing: DictationEntry {
        DictationEntry(
            title: "New Dictation",
            createdAt: .now.addingTimeInterval(-70),
            duration: 47,
            status: .transcribing,
            waveformSeed: 5
        )
    }

    static var previewGenerating: DictationEntry {
        DictationEntry(
            title: "Vertrag, Flüge, Rechnung",
            createdAt: .now.addingTimeInterval(-4 * 60),
            duration: 47,
            status: .generatingVariants,
            transcript: demoTranscript,
            waveformSeed: 5
        )
    }

    static var previewTranscriptionFailed: DictationEntry {
        DictationEntry(
            title: "New Dictation",
            createdAt: .now.addingTimeInterval(-9 * 60),
            duration: 47,
            status: .transcriptionFailed,
            waveformSeed: 5,
            transcriptionError: "Recording was interrupted."
        )
    }

    static var previewStreaming: DictationEntry {
        DictationEntry(
            title: "Vertrag, Flüge, Rechnung",
            createdAt: .now.addingTimeInterval(-4 * 60),
            duration: 47,
            status: .generatingVariants,
            transcript: demoTranscript,
            waveformSeed: 5,
            cleanedUpDraft: """
                Alex den aktualisierten Vertrag vor Freitag schicken. Das hat Priorität.

                ## Offen

                - Die Flüge für die Berlin
                """
        )
    }

    static var previewVariantFailed: DictationEntry {
        DictationEntry(
            title: "Vertrag, Flüge, Rechnung",
            createdAt: .now.addingTimeInterval(-4 * 60),
            duration: 47,
            status: .complete,
            transcript: demoTranscript,
            waveformSeed: 5,
            cleanedUpError: "claude exited with code 1."
        )
    }
}
