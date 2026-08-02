# frozen_string_literal: true

# Emits toast notifications over Turbo Streams by appending to the persistent
# viewport rendered once per layout (see PanelsUI::ToastViewport). Centralises
# the target id, partial path, and locals shape that were previously copy-pasted
# across ~18 controller actions.
#
#   render turbo_stream: toast_stream("Saved", type: :success)
#
#   render turbo_stream: [
#     turbo_stream.replace("photos", partial: "..."),
#     toast_stream("Photo removed", type: :success)
#   ]
module Toastable
  extend ActiveSupport::Concern

  private

  # Builds (does not render) a Turbo Stream tag appending a toast trigger, so it
  # can be composed into a multi-stream render array.
  def toast_stream(message, type: :default, description: nil)
    turbo_stream.append(
      PanelsUI::ToastViewport::DEFAULT_ID,
      partial: "shared/feedback/toast_trigger",
      locals: { message: message, type: type, description: description }
    )
  end

  # Convenience for actions that echo a flash key (:notice / :alert) as a toast.
  def toast_stream_for_flash(message, key)
    toast_stream(message, type: Toast.type_for_flash(key))
  end

  # Redirect counterpart of #toast_stream: carries a structured toast (with an
  # optional description/type the plain notice/alert flash can't express) across
  # the redirect via flash[:toast]. Extra options (e.g. status:) pass through to
  # redirect_to, and any flash already set on this request is preserved.
  def redirect_with_toast(url, message, type: :default, description: nil, action: nil, secondary_action: nil, **options)
    toast = { message: message, type: type, description: description, action: action, secondary_action: secondary_action }.compact
    redirect_to(url, **options, flash: { toast: toast })
  end
end
