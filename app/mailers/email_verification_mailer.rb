class EmailVerificationMailer < ApplicationMailer
  def verification_email(user:, token:)
    @user = user

    frontend_url = if Rails.env.development? || Rails.env.test?
      ENV.fetch("FRONTEND_URL", "http://localhost:5173")
    else
      ENV.fetch("FRONTEND_URL")
    end

    @verification_url = "#{frontend_url.chomp("/")}/verify-email?token=#{ERB::Util.url_encode(token)}"

    mail(
      to: @user.email,
      subject: "Verify your Mirrorline email address"
    )
  end
end
