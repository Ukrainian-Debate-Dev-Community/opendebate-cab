#!/bin/sh
# Rebuilds apps/ui/assets/vendor/tiptap.min.js, the rich text editor's
# library (TipTap on ProseMirror, MIT), as one minified ES module: npm
# and esbuild run in a temporary folder, nothing of them stays in the
# repo and the image build needs no npm. Non-ASCII characters come out
# as \u escapes. To move the pin, change TIPTAP and run:
#
#   sh tools/vendor/tiptap.sh
#
# ui's rich_editor.js imports what the entry below exports.
set -eu

TIPTAP=3.34.0
ESBUILD=0.25.4

root=$(cd "$(dirname "$0")/../.." && pwd)
out="$root/apps/ui/assets/vendor/tiptap.min.js"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$tmp"
npm init -y >/dev/null
npm install --no-audit --no-fund --save-exact \
  "@tiptap/core@$TIPTAP" "@tiptap/pm@$TIPTAP" "@tiptap/starter-kit@$TIPTAP" \
  "@tiptap/extension-image@$TIPTAP" "@tiptap/extensions@$TIPTAP" \
  "esbuild@$ESBUILD" >/dev/null

cat > entry.js <<'JS'
export {Editor, Node} from "@tiptap/core"
export {StarterKit} from "@tiptap/starter-kit"
export {Image} from "@tiptap/extension-image"
export {Placeholder} from "@tiptap/extensions"
JS

npx esbuild entry.js --bundle --format=esm --minify --target=es2020 \
  --charset=ascii --legal-comments=none --metafile=meta.json --outfile=bundle.js

# every package that went into the bundle, with its version and licence
packages=$(node -e '
  const fs = require("fs")
  const names = new Set()
  for (const input of Object.keys(JSON.parse(fs.readFileSync("meta.json", "utf8")).inputs)) {
    const m = input.match(/node_modules\/((?:@[^/]+\/)?[^/]+)\//)
    if (m) names.add(m[1])
  }
  for (const name of [...names].sort()) {
    const p = JSON.parse(fs.readFileSync("node_modules/" + name + "/package.json", "utf8"))
    console.log(" *   " + name + " " + p.version + " (" + p.license + ")")
  }
')

{
  cat <<HEAD
/*!
 * TipTap $TIPTAP (https://tiptap.dev, https://github.com/ueberdosis/tiptap)
 * on ProseMirror (https://prosemirror.net), vendored for ui's rich text
 * editor (rich_editor.js): Editor, Node, StarterKit, Image and Placeholder as
 * one ES module, built by tools/vendor/tiptap.sh with esbuild $ESBUILD;
 * non-ASCII characters written as \\u escapes. Do not edit by hand.
 *
 * The packages in it, all under the MIT License:
$packages
 *
 * (The MIT License)
 *
 * Copyright (c) 2025, Tiptap GmbH
 * Copyright (C) 2015-2017 by Marijn Haverbeke <marijn@haverbeke.berlin> and others
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * 'Software'), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
HEAD
  cat bundle.js
} > "$out"

echo "wrote $out ($(wc -c < "$out" | tr -d ' ') bytes, $(gzip -9c "$out" | wc -c | tr -d ' ') gzipped)"
