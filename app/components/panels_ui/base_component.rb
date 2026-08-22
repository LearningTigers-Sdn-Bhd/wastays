# frozen_string_literal: true

module PanelsUI
  # Base class for every PanelsUI primitive. The variant DSL (`style` /
  # `class_for`) lives in TailwindVariants; see that file for the how and why.
  class BaseComponent < ViewComponent::Base
    include TailwindVariants
  end
end
