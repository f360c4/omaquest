import QtQuick
import Quickshell
import Quickshell.Io

// Dictionary loader for the panel's user-facing strings.
//
// The Omarchy shell carries no translation machinery of its own, so the plugin
// brings its own: one flat JSON file per language under i18n/, all sharing the
// exact same keys (enforced by tools/check-i18n.sh). English is the fallback and
// covers any key a translation is missing, so a partial file degrades to
// English instead of showing a raw key.
//
// Owned by Service.qml, which every panel reads through: the bar mounts a
// widget per monitor, and one dictionary answering for all of them is both
// cheaper and impossible to get out of step with itself.
QtObject {
  id: root

  // "auto" follows $LANG; anything else must be one of `supported`.
  property string language: "auto"

  readonly property var supported: ["en", "pt-BR"]
  readonly property string fallbackCode: "en"
  readonly property string code: resolveCode(language)

  property var strings: ({})
  property var fallbackStrings: ({})

  // i18n/ sits next to this file, both in the repo and in the installed plugin
  // directory, so resolving against our own URL works in either place.
  function dictPath(languageCode) {
    return Qt.resolvedUrl("i18n/" + languageCode + ".json").toString().replace(/^file:\/\//, "")
  }

  // "pt_BR.UTF-8" -> "pt-BR"; "de_DE.UTF-8" -> "de"; anything unmatched -> "en".
  function resolveCode(requested) {
    if (requested && requested !== "auto") {
      return supported.indexOf(requested) !== -1 ? requested : fallbackCode
    }
    var env = String(Quickshell.env("LANG") || "")
    var tag = env.split(".")[0].split("@")[0].replace("_", "-")
    if (tag === "") return fallbackCode
    if (supported.indexOf(tag) !== -1) return tag
    var base = tag.split("-")[0]
    if (supported.indexOf(base) !== -1) return base
    return fallbackCode
  }

  function parse(text) {
    if (!text) return {}
    try {
      var parsed = JSON.parse(text)
      return parsed && typeof parsed === "object" ? parsed : {}
    } catch (e) {
      console.warn("Omaquest I18n: cannot parse dictionary:", e)
      return {}
    }
  }

  // Look up `key`, then fill {placeholders} from `vars`. Every message is a
  // whole sentence under one key — never assembled from fragments, because
  // word order differs across the seven languages.
  function t(key, vars) {
    var text = strings[key]
    if (text === undefined) text = fallbackStrings[key]
    if (text === undefined) return key
    if (!vars) return text
    return String(text).replace(/\{(?:([aA]):)?(\w+)\}/g, function(match, article, name) {
      if (vars[name] === undefined) return match
      var value = String(vars[name])
      if (!article) return value
      return indefinite(value, article === "A") + " " + value
    })
  }

  // `{a:race}` renders "an Orc" and "a Human"; `{A:race}` capitalises it for
  // the start of a sentence.
  //
  // English markup, used only in en.json. A dictionary that does not want it
  // simply does not write it — and because a missing key falls back to the
  // English string, the rule has to work regardless of which language is
  // loaded, so it never asks.
  //
  // The real rule is the sound, not the letter ("a unicorn", "an hour"), but
  // every word this is ever applied to is a race or a calling, and there are
  // eleven of them.
  function indefinite(word, capital) {
    var vowel = /^[aeiou]/i.test(String(word))
    if (capital) return vowel ? "An" : "A"
    return vowel ? "an" : "a"
  }

  property FileView fallbackFile: FileView {
    path: root.dictPath(root.fallbackCode)
    watchChanges: false
    printErrors: true
    onLoaded: root.fallbackStrings = root.parse(text())
    onLoadFailed: root.fallbackStrings = ({})
  }

  property FileView dictFile: FileView {
    path: root.dictPath(root.code)
    watchChanges: false
    printErrors: false
    onLoaded: root.strings = root.parse(text())
    onLoadFailed: root.strings = ({})
  }
}
