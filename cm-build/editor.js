import { EditorView, basicSetup } from 'codemirror';
import { EditorState, Compartment } from '@codemirror/state';
import { oneDark } from '@codemirror/theme-one-dark';
import { python }     from '@codemirror/lang-python';
import { javascript } from '@codemirror/lang-javascript';
import { html }       from '@codemirror/lang-html';
import { css }        from '@codemirror/lang-css';
import { json }       from '@codemirror/lang-json';
import { sql }        from '@codemirror/lang-sql';
import { xml }        from '@codemirror/lang-xml';
import { markdown }   from '@codemirror/lang-markdown';
import { rust }       from '@codemirror/lang-rust';
import { cpp }        from '@codemirror/lang-cpp';
import { java }       from '@codemirror/lang-java';
import { go }         from '@codemirror/lang-go';
import { php }        from '@codemirror/lang-php';
import { yaml }       from '@codemirror/lang-yaml';
import { StreamLanguage } from '@codemirror/language';
import { shell }  from '@codemirror/legacy-modes/mode/shell';
import { toml }   from '@codemirror/legacy-modes/mode/toml';
import { nginx }  from '@codemirror/legacy-modes/mode/nginx';
import { ruby }   from '@codemirror/legacy-modes/mode/ruby';

const langMap = {
  python:     python(),
  javascript: javascript(),
  typescript: javascript({ typescript: true }),
  html:       html(),
  css:        css(),
  json:       json(),
  sql:        sql(),
  xml:        xml(),
  markdown:   markdown(),
  rust:       rust(),
  c:          cpp(),
  cpp:        cpp(),
  java:       java(),
  go:         go(),
  php:        php({ plain: true }),
  yaml:       yaml(),
  bash:       StreamLanguage.define(shell),
  toml:       StreamLanguage.define(toml),
  nginx:      StreamLanguage.define(nginx),
  ruby:       StreamLanguage.define(ruby),
};

function initEditor() {
  const textarea = document.getElementById('content-hidden');
  const wrapper  = document.getElementById('cm-wrapper');
  const langSel  = document.getElementById('lang-select');
  const form     = document.getElementById('paste-form');

  if (!textarea || !wrapper) return;

  const langComp = new Compartment();

  function getLangExt(name) {
    return langMap[name] || [];
  }

  let view = new EditorView({
    state: EditorState.create({
      doc: textarea.value,
      extensions: [
        basicSetup,
        oneDark,
        EditorView.lineWrapping,
        langComp.of(getLangExt(langSel.value)),
      ],
    }),
    parent: wrapper,
  });

  // Cambiar lenguaje dinámicamente con Compartment (sin recrear el editor)
  langSel.addEventListener('change', () => {
    view.dispatch({
      effects: langComp.reconfigure(getLangExt(langSel.value)),
    });
    view.focus();
  });

  // Volcar contenido al textarea oculto antes del submit
  form.addEventListener('submit', (e) => {
    const content = view.state.doc.toString();
    textarea.value = content;
    if (!content.trim()) {
      e.preventDefault();
      wrapper.style.borderColor = 'var(--danger)';
      view.focus();
    }
  });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initEditor);
} else {
  initEditor();
}
