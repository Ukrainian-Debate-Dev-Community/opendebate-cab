// The contact-field helpers as a bundle of their own
// (/assets/js/contact-fields.js), for pages without LiveView that show a
// :phone / :email / :telegram block: the phone library is large, so only
// those pages load it, with <script defer src=".../assets/js/contact-fields.js">.
import {installContactFields, mountPhoneFields} from "./contact_fields"

const start = () => {
  installContactFields()
  mountPhoneFields()
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start)
else start()
