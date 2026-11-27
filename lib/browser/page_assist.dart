import 'package:zerotrust_browser/browser/read_aloud.dart';
import 'package:zerotrust_browser/browser/reader.dart';

/// The page's article as plain text for ZT Assist: the title, then the
/// paragraphs and headings one per line. The same text that is read aloud.
String pageTextForAssist(Article article) =>
    speechParts(article.content, title: article.title).join('\n');

/// Whether [text] is written mostly in Hebrew letters.
bool mostlyHebrew(String text) {
  int hebrew = 0;
  int latin = 0;
  for (final int rune in text.runes) {
    if (rune >= 0x05D0 && rune <= 0x05EA) {
      hebrew++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A)) {
      latin++;
    }
  }
  return hebrew > latin;
}

/// What ZT Assist is told when the user asks about the page: answer from
/// the page only, and say so when the page has no answer. In the
/// question's own language, which the model then answers in.
String pageQuestionInstruction(String question) {
  final String asked = question.replaceAll(RegExp(r'\s+'), ' ').trim();
  return mostlyHebrew(asked)
      ? 'ענה על השאלה לפי הטקסט שבהמשך בלבד. אם התשובה לא נמצאת בטקסט, '
            'אמור שהיא לא נמצאת בדף.\n'
            'השאלה: $asked\n\n'
            'הטקסט:'
      : 'Answer the question using only the text below. If the text does '
            'not answer it, say that the page does not say.\n'
            'Question: $asked\n\n'
            'The text:';
}
