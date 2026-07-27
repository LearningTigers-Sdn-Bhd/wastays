# frozen_string_literal: true

module PanelsUIInteractionHelper
  def open_panels_ui_popover(trigger:, panel:)
    wait_for_stimulus_controller(trigger, "panels-ui--popover")
    page.execute_script(<<~JS)
      (() => {
        const trigger = document.querySelector(#{trigger.to_json})
        if (!trigger) throw new Error(#{"popover trigger not found: #{trigger}".to_json})
        trigger.focus()
        trigger.click()
      })()
    JS
    find("#{panel}:popover-open", visible: :visible)
  end
end

RSpec.configure do |config|
  config.include PanelsUIInteractionHelper, type: :system
end
