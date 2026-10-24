// The standalone contact-field helpers (/assets/js/contact-fields.js)
// for sites that render cab's :phone / :email / :telegram blocks on
// their own pages: load it with <script defer src=".../assets/js/contact-fields.js">.
import {installContactFields, mountPhoneFields} from "./contact_fields"

const start = () => {
  installContactFields()
  mountPhoneFields()
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start)
else start()
