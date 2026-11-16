class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("GMAIL_USERNAME", "markpaul.dev@gmail.com")
  layout "mailer"
end
