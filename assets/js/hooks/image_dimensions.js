// Reads each picked image's natural width/height in the browser and pushes them
// to the server keyed by filename, so dimensions are known when the upload is
// consumed. Listens on the file input inside the upload form.
export const ImageDimensions = {
  mounted() {
    this.el.addEventListener("input", (e) => {
      if (e.target.type !== "file") return
      for (const file of e.target.files) {
        const url = URL.createObjectURL(file)
        const img = new Image()
        img.onload = () => {
          this.pushEvent("set_dimensions", {
            name: file.name,
            width: img.naturalWidth,
            height: img.naturalHeight,
          })
          URL.revokeObjectURL(url)
        }
        img.src = url
      }
    })
  },
}
