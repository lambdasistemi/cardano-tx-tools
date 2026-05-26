document.addEventListener("DOMContentLoaded", function () {
  var synth = window.speechSynthesis;
  if (!synth) return;

  var playing = null;
  var paused = false;
  var queue = [];
  var currentIndex = 0;
  var pauseTimer = null;
  var speechData = null;
  var generation = 0;
  var selectedVoice = null;
  var voices = [];

  function pageLang() {
    return (
      document.documentElement.getAttribute("lang") ||
      navigator.language ||
      "en"
    ).toLowerCase();
  }

  function languageParts(lang) {
    var normalized = (lang || "en").toLowerCase();
    return {
      full: normalized,
      primary: normalized.split("-")[0] || "en",
    };
  }

  function voiceScore(voice, wanted) {
    var voiceLang = (voice.lang || "").toLowerCase();
    if (voiceLang === wanted.full) return 4;
    if (voiceLang.indexOf(wanted.primary + "-") === 0) return 3;
    if (wanted.primary === "en" && voiceLang.indexOf("en-") === 0) return 2;
    if (wanted.primary === "en" && voiceLang === "en") return 2;
    return 0;
  }

  function findPreferredVoice(available, savedName, wanted) {
    if (savedName) {
      var saved = available.find(function (voice) {
        return voice.name === savedName && voiceScore(voice, wanted) > 0;
      });
      if (saved) return saved;
    }

    return available
      .slice()
      .sort(function (a, b) {
        var byLang = voiceScore(b, wanted) - voiceScore(a, wanted);
        if (byLang !== 0) return byLang;
        return a.name.localeCompare(b.name);
      })[0];
  }

  function createVoiceSelector() {
    var container = document.createElement("div");
    container.style.cssText =
      "position:fixed;bottom:1rem;right:1rem;z-index:1000;" +
      "background:var(--md-default-bg-color, #1a1b26);" +
      "border:1px solid var(--md-default-fg-color--lighter, #3b4261);" +
      "border-radius:6px;padding:6px 10px;font-size:13px;" +
      "color:var(--md-default-fg-color, #c0caf5);opacity:0.7;";
    container.addEventListener("mouseenter", function () {
      container.style.opacity = "1";
    });
    container.addEventListener("mouseleave", function () {
      container.style.opacity = "0.7";
    });

    var label = document.createElement("span");
    label.textContent = "Voice ";
    container.appendChild(label);

    var select = document.createElement("select");
    select.style.cssText =
      "background:var(--md-default-bg-color, #1a1b26);" +
      "color:var(--md-default-fg-color, #c0caf5);" +
      "border:1px solid var(--md-default-fg-color--lighter, #3b4261);" +
      "border-radius:4px;padding:2px 4px;font-size:13px;" +
      "max-width:250px;";

    function populateVoices() {
      var wanted = languageParts(pageLang());
      var saved = localStorage.getItem("read-aloud-voice");
      voices = synth.getVoices().slice().sort(function (a, b) {
        var byLang = voiceScore(b, wanted) - voiceScore(a, wanted);
        if (byLang !== 0) return byLang;
        return a.name.localeCompare(b.name);
      });
      if (voices.length === 0) return;

      selectedVoice = findPreferredVoice(voices, saved, wanted);
      select.innerHTML = "";
      voices.forEach(function (voice, i) {
        var option = document.createElement("option");
        option.value = i;
        option.textContent = voice.name + " (" + voice.lang + ")";
        if (selectedVoice && voice.name === selectedVoice.name) {
          option.selected = true;
        }
        select.appendChild(option);
      });
    }

    select.addEventListener("change", function () {
      var idx = parseInt(select.value, 10);
      selectedVoice = voices[idx];
      localStorage.setItem("read-aloud-voice", selectedVoice.name);
    });

    populateVoices();
    if (synth.onvoiceschanged !== undefined) {
      synth.onvoiceschanged = populateVoices;
    }

    container.appendChild(select);
    document.body.appendChild(container);
  }

  createVoiceSelector();

  var pagePath = window.location.pathname
    .replace(/\/$/, "")
    .replace(/\/index$/, "");
  var speechUrl = pagePath + ".speech.json";
  if (pagePath === "" || pagePath === "/") {
    speechUrl = "/index.speech.json";
  }

  fetch(speechUrl)
    .then(function (response) {
      if (response.ok) return response.json();
      return null;
    })
    .then(function (data) {
      speechData = data;
    })
    .catch(function () {
      speechData = null;
    });

  function extractText(el) {
    var cloned = el.cloneNode(true);
    cloned
      .querySelectorAll("pre, code, .mermaid, table, .md-nav, .md-footer")
      .forEach(function (node) {
        node.remove();
      });
    return cloned.textContent.replace(/\s+/g, " ").trim();
  }

  function getHeadingText(heading) {
    var cloned = heading.cloneNode(true);
    cloned.querySelectorAll("button, a.headerlink").forEach(function (el) {
      el.remove();
    });
    return cloned.textContent.replace(/\s+/g, " ").trim();
  }

  function collectSegments(heading, elements) {
    var segments = [];
    var title = getHeadingText(heading);
    if (title.length > 0) {
      segments.push({ text: title + ".", pause: 500 });
    }
    elements.forEach(function (el) {
      if (el.tagName === "UL" || el.tagName === "OL") {
        el.querySelectorAll(":scope > li").forEach(function (li) {
          var text = extractText(li);
          if (text.length > 0) {
            segments.push({ text: text + ".", pause: 300 });
          }
        });
      } else {
        var text = extractText(el);
        if (text.length > 0) {
          segments.push({ text: text, pause: 200 });
        }
      }
    });
    return segments;
  }

  function getSectionId(heading) {
    return (heading.id || heading.textContent.trim().toLowerCase())
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "");
  }

  function createButton() {
    var btn = document.createElement("button");
    btn.textContent = "\u25b6";
    btn.title = "Read aloud (click: play/pause)";
    btn.style.cssText =
      "background:none;border:1px solid var(--md-default-fg-color--lighter);" +
      "border-radius:4px;cursor:pointer;font-size:14px;padding:2px 8px;" +
      "margin-left:8px;opacity:0.5;vertical-align:middle;color:inherit;";
    btn.addEventListener("mouseenter", function () {
      btn.style.opacity = "1";
    });
    btn.addEventListener("mouseleave", function () {
      if (playing !== btn) btn.style.opacity = "0.5";
    });
    return btn;
  }

  function fullStop(btn) {
    generation++;
    if (pauseTimer) {
      clearTimeout(pauseTimer);
      pauseTimer = null;
    }
    synth.cancel();
    queue = [];
    currentIndex = 0;
    paused = false;
    if (btn) {
      btn.textContent = "\u25b6";
      btn.title = "Read aloud (click: play/pause)";
      btn.style.opacity = "0.5";
    }
    playing = null;
  }

  function pauseSpeaking(btn) {
    synth.pause();
    if (pauseTimer) {
      clearTimeout(pauseTimer);
      pauseTimer = null;
    }
    paused = true;
    btn.textContent = "\u25b6";
    btn.title = "Resume";
  }

  function resumeSpeaking(btn) {
    paused = false;
    btn.textContent = "\u275a\u275a";
    btn.title = "Pause";
    synth.resume();
  }

  function speakSegment(btn, gen) {
    if (gen !== generation) return;

    if (currentIndex >= queue.length) {
      fullStop(btn);
      return;
    }
    var seg = queue[currentIndex];
    if (seg.skip) {
      currentIndex++;
      speakSegment(btn, gen);
      return;
    }

    var utterance = new SpeechSynthesisUtterance(seg.text);
    utterance.lang = pageLang();
    utterance.rate = seg.rate || 1.0;
    if (selectedVoice) utterance.voice = selectedVoice;
    utterance.onend = function () {
      if (gen !== generation) return;
      currentIndex++;
      var pause = seg.pause || 200;
      if (pause > 0) {
        pauseTimer = setTimeout(function () {
          pauseTimer = null;
          speakSegment(btn, gen);
        }, pause);
      } else {
        speakSegment(btn, gen);
      }
    };
    synth.speak(utterance);
  }

  document.querySelectorAll("h2, h3").forEach(function (heading) {
    var section = [];
    var sibling = heading.nextElementSibling;
    while (sibling && !sibling.matches("h2, h3")) {
      section.push(sibling);
      sibling = sibling.nextElementSibling;
    }
    if (section.length === 0) return;

    var fallbackSegments = collectSegments(heading, section);
    if (fallbackSegments.length === 0) return;

    var sectionId = getSectionId(heading);
    var btn = createButton();
    heading.appendChild(btn);

    btn.addEventListener("click", function (e) {
      e.preventDefault();
      e.stopPropagation();

      if (playing === btn && paused) {
        resumeSpeaking(btn);
        return;
      }

      if (playing === btn && !paused) {
        pauseSpeaking(btn);
        return;
      }

      if (playing) {
        fullStop(playing);
      }

      if (speechData && speechData[sectionId]) {
        queue = speechData[sectionId];
      } else {
        queue = fallbackSegments;
      }

      currentIndex = 0;
      paused = false;
      btn.textContent = "\u275a\u275a";
      btn.title = "Pause";
      btn.style.opacity = "1";
      playing = btn;
      speakSegment(btn, generation);
    });
  });
});
