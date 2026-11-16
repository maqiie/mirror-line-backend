class PasswordResetMailer < ApplicationMailer
  def reset_email(user:, token:)
    @user = user
    frontend_url = if Rails.env.development? || Rails.env.test?
      ENV.fetch("FRONTEND_URL", "http://localhost:5173")
    else
      ENV.fetch("FRONTEND_URL")
    end

    @reset_url = "#{frontend_url.chomp("/")}/reset-password?token=#{ERB::Util.url_encode(token)}"

    mail(
      to: @user.email,
      subject: "Reset your Mirrorline password"
    )
  end
end
