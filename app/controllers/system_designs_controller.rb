# frozen_string_literal: true

# Living showcase for the PanelsUI primitive component library. It uses a dedicated
# layout so the real Tailwind and importmap assets are present without application
# navigation, widgets, or footer chrome. Not exposed in production (see routes.rb).
class SystemDesignsController < ApplicationController
  layout "system_design"

  def index; end
end
