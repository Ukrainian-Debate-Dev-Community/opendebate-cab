#!/bin/sh
# Rebuilds the full-screen photo viewer's library, PhotoSwipe (MIT), for
# ui's photo_viewer.js: apps/ui/assets/vendor/photoswipe.min.js (the
# core as one minified ES module) and apps/ui/assets/vendor/photoswipe.css
# (its stylesheet, minified; ui.css imports it). npm and esbuild run in
# a temporary folder, nothing of them stays in the repo and the image
# build needs no npm. Non-ASCII characters come out as \u escapes. To
# move the pin, change PHOTOSWIPE and run:
#
#   sh tools/vendor/photoswipe.sh
set -eu

PHOTOSWIPE=5.4.4
ESBUILD=0.25.4

root=$(cd "$(dirname "$0")/../.." && pwd)
vendor="$root/apps/ui/assets/vendor"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$tmp"
npm init -y >/dev/null
npm install --no-audit --no-fund --save-exact "photoswipe@$PHOTOSWIPE" "esbuild@$ESBUILD" >/dev/null

cat > entry.js <<'JS'
export {default as PhotoSwipe} from "photoswipe"
JS

npx esbuild entry.js --bundle --format=esm --minify --target=es2020 \
  --charset=ascii --legal-comments=none --outfile=bundle.js
npx esbuild node_modules/photoswipe/dist/photoswipe.css --minify \
  --charset=ascii --legal-comments=none --outfile=bundle.css

head() {
  cat <<HEAD
/*!
 * PhotoSwipe $PHOTOSWIPE (https://photoswipe.com, https://github.com/dimsemenov/PhotoSwipe),
 * vendored for ui's full-screen photo viewer (photo_viewer.js): $1,
 * built by tools/vendor/photoswipe.sh with esbuild $ESBUILD; non-ASCII
 * characters written as \\u escapes. Do not edit by hand.
 *
 * (The MIT License)
 *
 * Copyright (c) 2014-2022 Dmitry Semenov, https://dimsemenov.com
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
}

{ head "the PhotoSwipe class as one ES module"; cat bundle.js; } > "$vendor/photoswipe.min.js"
{ head "its stylesheet, imported by ui.css"; cat bundle.css; } > "$vendor/photoswipe.css"

for f in photoswipe.min.js photoswipe.css; do
  echo "wrote $vendor/$f ($(wc -c < "$vendor/$f" | tr -d ' ') bytes, $(gzip -9c "$vendor/$f" | wc -c | tr -d ' ') gzipped)"
done
