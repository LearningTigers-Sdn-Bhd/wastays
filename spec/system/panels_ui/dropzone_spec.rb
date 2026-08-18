# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Dropzone", type: :system do
  let(:image_path) { Rails.root.join("spec/fixtures/files/sample_image.jpg") }
  let(:second_image_path) { Rails.root.join("public/icon.png") }
  let(:third_image_path) { Rails.root.join("public/icon.svg") }

  before { visit_when_loaded "/system-design?only=file_upload_preview" }

  # The dropzone controller re-renders its attachments on connect, which can replace
  # server-rendered nodes mid-interaction. Query + click atomically in one JS call,
  # scoped to the file-upload section, so no re-render can stale a handle between
  # find and click.
  def click_in_upload_section(selector)
    page.execute_script(<<~JS, selector)
      const section = document.querySelector("#file-upload-preview-heading").closest("section")
      const el = section.querySelector(arguments[0])
      if (!el) throw new Error(`element not found: ${arguments[0]}`)
      el.click()
    JS
  end

  it "renders native inputs, attachments, and dropzones in both themes" do
    expect(page).to have_css("#file-upload-preview-heading", text: "File uploads")
    expect(page).to have_css("[data-theme='panel-light'] input.panel-input[type='file']", visible: :all)
    expect(page).to have_css("[data-theme='panel-dark'] input.panel-input[type='file']", visible: :all)
    expect(page).to have_css("[data-theme='panel-light'] .panel-dropzone")
    expect(page).to have_css("[data-theme='panel-dark'] .panel-dropzone")
    expect(page).to have_css("[data-theme='panel-light'] .panel-attachment[data-state='uploading']")
    expect(page).to have_css("[data-theme='panel-dark'] .panel-attachment[data-state='error']")
    expect(page).to have_css("[data-theme='panel-light'] .panel-attachment[data-state='ready']", text: "Ready to upload")
    expect(page).to have_css("[data-theme='panel-dark'] .panel-attachment[data-state='uploaded']", text: "Uploaded · 1.8 MB")
    expect(page).to have_css(".panel-attachment[data-state='uploading']", text: "Uploading · 61%")
    expect(page).to have_no_css(".panel-attachment progress")

    styles = page.evaluate_script(<<~JS)
      (() => {
        const section = document.getElementById("file-upload-preview-heading").closest("section")
        const theme = section.querySelector("[data-theme='panel-light']")
        const readyMedia = theme.querySelector(".panel-attachment[data-state='ready'] .panel-attachment__media")
        const error = theme.querySelector(".panel-attachment[data-state='error']")
        const errorMedia = error.querySelector(".panel-attachment__media")
        return {
          readyBackground: getComputedStyle(readyMedia).backgroundColor,
          errorBackground: getComputedStyle(errorMedia).backgroundColor,
          errorIcon: getComputedStyle(errorMedia).color,
          errorText: getComputedStyle(error.querySelector(".panel-attachment__description")).color
        }
      })()
    JS

    expect(styles.fetch("errorBackground")).not_to eq(styles.fetch("readyBackground"))
    expect(styles.fetch("errorIcon")).to eq(styles.fetch("errorText"))
  end

  it "activates the full-card trigger without trapping the attachment action" do
    attachment_scope = "[data-theme='panel-light'] .panel-attachment[data-state='ready']"
    trigger_selector = "#{attachment_scope} .panel-attachment__trigger[aria-label='Open selected-file.pdf']"
    action_selector = "#{attachment_scope} button[aria-label='Remove selected-file.pdf']"

    layering = page.evaluate_script(<<~JS, trigger_selector, action_selector)
      (() => {
        const section = document.querySelector("#file-upload-preview-heading").closest("section")
        return {
          trigger: Number(getComputedStyle(section.querySelector(arguments[0])).zIndex),
          action: Number(getComputedStyle(section.querySelector(arguments[1]).closest(".panel-attachment__actions")).zIndex)
        }
      })()
    JS
    expect(layering.fetch("action")).to be > layering.fetch("trigger")

    # The page's scrollspy owns location.hash, so assert the full-card trigger's
    # activation directly: the remove action must not activate the trigger link,
    # while clicking the trigger itself must (navigating to the card's target).
    page.execute_script(<<~JS, trigger_selector)
      const section = document.querySelector("#file-upload-preview-heading").closest("section")
      window.__attachmentTriggerHref = null
      section.querySelector(arguments[0]).addEventListener("click", (event) => {
        event.preventDefault()
        window.__attachmentTriggerHref = event.currentTarget.getAttribute("href")
      })
    JS

    click_in_upload_section(action_selector)
    expect(page.evaluate_script("window.__attachmentTriggerHref")).to be_nil

    click_in_upload_section(trigger_selector)
    expect(page.evaluate_script("window.__attachmentTriggerHref")).to eq("#file-upload-preview-heading")
  end

  it "accumulates unique files, renders image attachments, removes files, and clears the selection" do
    input_id = "file_upload_panel_light_photos"

    attach_file(input_id, image_path, make_visible: true)
    expect(page).to have_css(".panel-attachment[data-file-key] .panel-attachment__title", text: "sample_image.jpg")
    expect(page).to have_css(".panel-dropzone__thumbnail[alt='Preview of sample_image.jpg']")

    attach_file(input_id, second_image_path, make_visible: true)
    expect(page).to have_css(".panel-dropzone__selection-title", text: "2 selected files")
    expect(page).to have_css(".panel-attachment[data-file-key]", count: 2)

    attach_file(input_id, image_path, make_visible: true)
    expect(page).to have_css(".panel-attachment[data-file-key]", count: 2)

    page.find("button[aria-label='Remove sample_image.jpg']").click
    expect(page).to have_no_css(".panel-attachment__title", text: "sample_image.jpg")
    expect(page).to have_css(".panel-dropzone__selection-title", text: "1 selected file")

    page.find(".panel-dropzone__selection button", text: "Clear all").click
    expect(page).to have_no_css(".panel-attachment[data-file-key]")
    expect(page).to have_css(".panel-dropzone__selection[hidden]", visible: :all)
  end

  it "keeps accepted files while announcing count and size validation errors" do
    attach_file(
      "file_upload_panel_light_photos",
      [ image_path, second_image_path, third_image_path ],
      make_visible: true
    )

    expect(page).to have_css(".panel-attachment[data-file-key]", count: 2)
    expect(page).to have_css(".panel-dropzone__error[role='alert']", text: "Only 2 more files can be selected.")
    expect(page).to have_css(".panel-dropzone__surface[data-state='invalid']")
  end

  it "rejects dropped files with invalid types or excessive sizes" do
    dropzone = page.find("[data-theme='panel-light'] .panel-dropzone[data-panels-ui--dropzone-presentation-value='files']")

    page.execute_script(<<~JS, dropzone)
      const transfer = new DataTransfer()
      transfer.items.add(new File(["plain text"], "notes.txt", { type: "text/plain" }))
      const event = new Event("drop", { bubbles: true, cancelable: true })
      Object.defineProperty(event, "dataTransfer", { value: transfer })
      arguments[0].dispatchEvent(event)
    JS

    expect(dropzone).to have_css(".panel-dropzone__error", text: "notes.txt is not an accepted file type.")
    expect(dropzone).to have_no_css(".panel-attachment[data-file-key]")

    page.execute_script(<<~JS, dropzone)
      const transfer = new DataTransfer()
      transfer.items.add(new File([new Uint8Array(5 * 1024 * 1024 + 1)], "large.jpg", { type: "image/jpeg" }))
      const event = new Event("drop", { bubbles: true, cancelable: true })
      Object.defineProperty(event, "dataTransfer", { value: transfer })
      arguments[0].dispatchEvent(event)
    JS

    expect(dropzone).to have_css(".panel-dropzone__error", text: "large.jpg is larger than 5.0 MB.")
    expect(dropzone).to have_no_css(".panel-attachment[data-file-key]")
  end

  it "cleans up image object URLs and follows native form reset" do
    page.execute_script(<<~JS)
      window.__dropzoneRevokedUrls = []
      window.__nativeRevokeObjectURL = URL.revokeObjectURL.bind(URL)
      URL.revokeObjectURL = (url) => {
        window.__dropzoneRevokedUrls.push(url)
        window.__nativeRevokeObjectURL(url)
      }
    JS

    attach_file("file_upload_panel_light_photos", image_path, make_visible: true)
    expect(page).to have_css(".panel-attachment[data-file-key]", count: 1)

    page.find("button[aria-label='Remove sample_image.jpg']").click
    expect(page.evaluate_script("window.__dropzoneRevokedUrls.length")).to be >= 1

    attach_file("file_upload_panel_light_photos", image_path, make_visible: true)
    page.execute_script("document.querySelector('#file_upload_panel_light_photos').form.reset()")

    expect(page).to have_no_css(".panel-attachment[data-file-key]")
    expect(page).to have_css(".panel-dropzone__selection[hidden]", visible: :all)
  end

  it "tracks nested drag entry without flickering the drag state" do
    surface = page.find(
      "[data-theme='panel-light'] .panel-dropzone[data-panels-ui--dropzone-presentation-value='files'] " \
      ".panel-dropzone__surface"
    )

    page.execute_script(<<~JS, surface)
      const surface = arguments[0]
      const child = surface.querySelector(".panel-dropzone__icon")
      const dragEvent = (name, target) => {
        const event = new Event(name, { bubbles: true, cancelable: true })
        Object.defineProperty(event, "dataTransfer", { value: { types: ["Files"], dropEffect: "none" } })
        target.dispatchEvent(event)
      }
      dragEvent("dragenter", surface)
      dragEvent("dragenter", child)
      dragEvent("dragleave", child)
    JS

    expect(surface["data-state"]).to eq("dragging")

    page.execute_script(<<~JS, surface)
      const event = new Event("dragleave", { bubbles: true, cancelable: true })
      Object.defineProperty(event, "dataTransfer", { value: { types: ["Files"] } })
      arguments[0].dispatchEvent(event)
    JS

    expect(surface["data-state"]).to eq("idle")
  end

  it "replaces, stages removal, undoes removal, and exposes keyboard-focusable image actions" do
    dropzone = page.find("[data-theme='panel-light'] .panel-dropzone[data-panels-ui--dropzone-presentation-value='single_image']")
    expect(dropzone).to have_css("img[alt='Current hotel icon'][src='/icon.png']")
    image_layout = page.evaluate_script(<<~JS, dropzone)
      (() => {
        const surface = arguments[0].querySelector(".panel-dropzone__surface")
        const image = arguments[0].querySelector(".panel-dropzone__single-image > img")
        return {
          objectFit: getComputedStyle(image).objectFit,
          width: surface.getBoundingClientRect().width,
          height: surface.getBoundingClientRect().height
        }
      })()
    JS
    expect(image_layout.fetch("objectFit")).to eq("cover")
    expect(image_layout.fetch("width")).to be_within(1).of(image_layout.fetch("height"))

    dropzone.find(".panel-dropzone__single-image").hover
    expect(dropzone).to have_button("Replace")
    expect(dropzone).to have_button("Remove")

    replace_button = dropzone.find("button", text: "Replace")
    replace_button.send_keys(:tab)
    expect(dropzone).to have_css("button:focus")

    attach_file("file_upload_panel_light_icon", image_path, make_visible: true)
    expect(dropzone).to have_css("img[alt='Preview of sample_image.jpg']")
    expect(page.evaluate_script("document.querySelector('#file_upload_panel_light_remove_icon').value")).to eq("0")

    dropzone.find("button", text: "Remove").click
    expect(dropzone).to have_css(".panel-dropzone__pending-removal", text: "Icon will be removed when you save.")
    expect(page.evaluate_script("document.querySelector('#file_upload_panel_light_remove_icon').value")).to eq("1")
    expect(page.evaluate_script("document.querySelector('#file_upload_panel_light_icon').files.length")).to eq(0)

    dropzone.find("button", text: "Undo remove").click
    expect(dropzone).to have_css("img[alt='Current hotel icon'][src='/icon.png']")
    expect(page.evaluate_script("document.querySelector('#file_upload_panel_light_remove_icon').value")).to eq("0")

    page.execute_script(<<~JS, dropzone)
      const transfer = new DataTransfer()
      transfer.items.add(new File(["replacement"], "dropped.webp", { type: "image/webp" }))
      const event = new Event("drop", { bubbles: true, cancelable: true })
      Object.defineProperty(event, "dataTransfer", { value: transfer })
      arguments[0].dispatchEvent(event)
    JS

    expect(dropzone).to have_css("img[alt='Preview of dropped.webp']")
    expect(page.evaluate_script("document.querySelector('#file_upload_panel_light_remove_icon').value")).to eq("0")
  end
end
