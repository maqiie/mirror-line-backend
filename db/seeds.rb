# bin/rails db:seed
# Creates a demo login, one master and three followers (with links) that mirror the dashboard's demo data,
# and prints each EA token plus a ready-to-run command for the fake-terminal simulator.
# Dev convenience: tokens are re-issued on every run (the old ones stop working).
user = User.find_or_initialize_by(email: ENV.fetch("SEED_EMAIL", "admin@example.com"))
user.password = ENV.fetch("SEED_PASSWORD", "change-me-please") if user.new_record?
user.save!

def seed_account(user, attrs)
  acct = user.trading_accounts.find_or_create_by!(login: attrs[:login], server: attrs[:server]) { |a| a.assign_attributes(attrs) }
  [acct, acct.raw_token || acct.rotate_token!]
end

master, master_token = seed_account(user, name: "Main master",    role: "master", platform: "mt5", login: 51_872_304, broker: "Exness",      server: "Exness-MT5Real8")
alpha,  alpha_token  = seed_account(user, name: "Alpha follower", role: "slave",  platform: "mt5", login: 51_990_127, broker: "Exness",      server: "Exness-MT5Real8")
scalp,  scalp_token  = seed_account(user, name: "Scalp account",  role: "slave",  platform: "mt4", login: 8_841_932,  broker: "IC Markets",  server: "ICMarketsSC-Live07")
safe,   safe_token   = seed_account(user, name: "Safe growth",    role: "slave",  platform: "mt5", login: 70_031_845, broker: "Pepperstone", server: "Pepperstone-Edge12")

user.copy_links.find_or_create_by!(master_account: master, slave_account: alpha) { |l| l.assign_attributes(lot_mode: "multiplier",    lot_value: 0.5, max_slippage: 20) }
user.copy_links.find_or_create_by!(master_account: master, slave_account: scalp) { |l| l.assign_attributes(lot_mode: "fixed",         lot_value: 0.1, max_slippage: 15, symbol_suffix: ".m") }
user.copy_links.find_or_create_by!(master_account: master, slave_account: safe)  { |l| l.assign_attributes(lot_mode: "balance_ratio", lot_value: 1,   max_slippage: 30) }

puts "Dashboard login: #{user.email} / #{ENV.fetch('SEED_PASSWORD', 'change-me-please')}"
puts
puts "EA tokens:"
puts "  Main master    #{master_token}"
puts "  Alpha follower #{alpha_token}"
puts "  Scalp account  #{scalp_token}"
puts "  Safe growth    #{safe_token}"
puts
puts "Fake terminals (no MetaTrader needed):"
puts "  node tools/simulate_eas.mjs --master=#{master_token} --slaves=#{alpha_token},#{scalp_token},#{safe_token}"
