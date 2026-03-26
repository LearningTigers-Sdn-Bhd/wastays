module HotelPortal::OnboardingHelper
  def onboarding_step_status_icon(completed)
    if completed
      content_tag(:div, "✓", class: "flex-shrink-0 size-10 rounded-full bg-green-100 flex items-center justify-center text-green-600 font-bold")
    else
      yield # This will render the step number
    end
  end

  def onboarding_step_card_classes(completed)
    base = "bg-white border rounded-xl p-6 shadow-sm "
    if completed
      "#{base} border-green-200 bg-green-50"
    else
      "#{base} border-gray-200"
    end
  end

  def onboarding_step_content_classes(enabled)
    enabled ? "" : "opacity-50"
  end

  def onboarding_button_classes(completed)
    if completed
      "py-2 px-4 inline-flex items-center gap-x-2 text-sm font-semibold rounded-lg border border-transparent bg-green-600 text-white hover:bg-green-700"
    else
      "py-2 px-4 inline-flex items-center gap-x-2 text-sm font-semibold rounded-lg border border-transparent bg-blue-600 text-white hover:bg-blue-700"
    end
  end
end
