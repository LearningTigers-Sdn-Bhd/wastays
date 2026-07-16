# frozen_string_literal: true

# Single source of truth for toast notification vocabulary shared between the
# controller concern (Toastable) and the view helper (toast_flash_messages).
# Not an Active Record model — just the domain rules for how flash keys map to
# the toast types the JS controller understands (see toast_controller.js).
module Toast
  # Rails flash keys -> toast variant. Anything else falls back to "default".
  TYPE_BY_FLASH_KEY = {
    "notice" => "success",
    "alert" => "error"
  }.freeze

  def self.type_for_flash(key)
    TYPE_BY_FLASH_KEY.fetch(key.to_s, "default")
  end
end
