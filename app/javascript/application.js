// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import "trix"
import "@rails/actiontext"
import "@fortawesome/fontawesome-free/js/all"

window.addEventListener("trix-file-accept", function(event) {
  event.preventDefault()
  alert("File attachment not supported!")
})
