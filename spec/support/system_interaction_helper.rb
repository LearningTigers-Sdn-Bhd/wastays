# frozen_string_literal: true

module SystemInteractionHelper
  def wait_for_stimulus_controller(selector, identifier)
    synchronize_browser_state("#{identifier} Stimulus controller is not connected") do
      page.evaluate_script(<<~JS)
        (() => {
          const element = document.querySelector(#{selector.to_json})
          const identifier = #{identifier.to_json}
          const controllerRoot = element?.closest(`[data-controller~="${CSS.escape(identifier)}"]`)
          return Boolean(controllerRoot && window.Stimulus?.getControllerForElementAndIdentifier(controllerRoot, identifier))
        })()
      JS
    end
  end

  def wait_for_body_overflow(expected)
    synchronize_browser_state("expected body overflow to be #{expected.inspect}") do
      page.evaluate_script("document.body.style.overflow") == expected
    end
  end

  def click_via_javascript(selector)
    page.execute_script(<<~JS)
      (() => {
        const element = document.querySelector(#{selector.to_json})
        if (!element) throw new Error(#{"element not found: #{selector}".to_json})
        element.click()
      })()
    JS
  end

  def show_modal(id)
    page.execute_script(<<~JS)
      (() => {
        const dialog = document.getElementById(#{id.to_json})
        if (!dialog) throw new Error(#{"dialog not found: #{id}".to_json})
        if (!dialog.open) dialog.showModal()
      })()
    JS

    synchronize_browser_state("expected dialog ##{id} to finish opening") do
      page.evaluate_script(<<~JS)
        (() => {
          const dialog = document.getElementById(#{id.to_json})
          return Boolean(dialog?.open && dialog.hasAttribute("data-panels-open"))
        })()
      JS
    end
  end

  def wait_for_dialog_closed(id)
    synchronize_browser_state("expected dialog ##{id} to finish closing") do
      page.evaluate_script(<<~JS)
        (() => {
          const dialog = document.getElementById(#{id.to_json})
          return Boolean(dialog && !dialog.open && !dialog.hasAttribute("data-panels-open"))
        })()
      JS
    end
  end

  def dispatch_key(key, selector: nil)
    target = selector ? "document.querySelector(#{selector.to_json})" : "document.activeElement"
    page.execute_script(<<~JS)
      (() => {
        const target = #{target}
        if (!target) throw new Error("keyboard event target not found")
        target.dispatchEvent(new KeyboardEvent("keydown", {
          key: #{key.to_json},
          bubbles: true,
          cancelable: true,
          composed: true
        }))
      })()
    JS
  end

  private

  def synchronize_browser_state(message)
    page.document.synchronize do
      raise Capybara::ElementNotFound, message unless yield
    end
  end
end

RSpec.configure do |config|
  config.include SystemInteractionHelper, type: :system
end
