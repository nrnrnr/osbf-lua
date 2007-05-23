--- returns table of user-editable configuration parameters


local threshold = 20 -- low score range, or reinforcement zone,  
                     -- around min_pR_success. Use 20            
                     -- during the pre-training phase for better 
                     -- accuracy and reduce to 10 or less later, 
                     -- for less burden with daily trainings.    

return {
  -- command password
  pwd = "your_password_here", -- no spaces allowed

  -- database files
  ham_db  = "ham.cfc",
  spam_db = "spam.cfc",

  min_pR_success    = 0,  -- min pR to be considered as ham


  threshold         = threshold, -- half the width of the reinforcement range

  -- tags for the subject line
  tag_subject     = true,
  tag_spam        = "[--]",  -- tag for spam messages
  tag_unsure_spam = "[-]",   -- tag for low abs score spam messages
  tag_unsure_ham  = "[+]",   -- tag for low score ham messages
  tag_ham         = "",      -- tag for ham messages

  -- training result subjects
  trained_as_spam        = "Trained as spam",
  trained_as_ham     = "Trained as ham",
  training_not_necessary = "Training not necessary: score = %.2f; " ..
                           "out of learning region: [-%.1f, %.1f]",

  -- To disable sfids, make false.
  use_sfid     = true,

  -- SFID rightid - change it to personalize for your site.
  rightid        = "spamfilter.osbf.lua",

  -- In which headers to insert the SFID? Uncomment exactly one of them:
  --insert_sfid_in  = {"references"},
  --insert_sfid_in  = {"message-id"},
  insert_sfid_in  = {"references", "message-id"},

  -- log options
  save_for_training = true,  -- save msg for later training
  log_incoming      = true,  -- log all incoming messages
  log_learned       = true,  -- log learned messages
  log_dir           = "log", -- relative to the user osbf-lua dir

  -- If use_sfid_subdir is true, messages cached for later training
  -- are saved under a subdir under log_dir, formed by the day of
  -- the month and the time the message arrived (DD/HH), to avoid excessive
  -- files per dir. The subdirs must be created before you enable this option.
  use_sfid_subdir = false,

  -- Count classifications? To turn off, set to false.
  count_classifications = true,

  -- This option specifies that the original message will be written to stdout
  -- after a training, with the correct tag. To have the original behavior,
  -- that is, just a report message, comment this option out.
  output       = "message",

  -- Set remove_body_threshold to the score below which you want the
  -- message body removed. Use this option after you have well trained
  -- databases:
  --remove_body_threshold = -2 * threshold,
  remove_body_threshold = false,

  -- Language to use in the cache-report training message.
  -- Default of true uses the user's locale; otherwise
  -- we understand 'en_US' and 'pt_BR'.
  report_locale = true,

  -- Command to send pre-formatted command messages.
  -- The %s in the command will be replaced with the name
  -- of a file containing the pre-formatted
  -- message to be sent.
  mail_cmd = "/usr/lib/sendmail -it < %s",

  -- Limit on the number of messages in a single cache report.
  cache_report_limit = 50,

  -- Order of messages in cache report.
  -- '<' => older to newer; '>' => newer to older
  cache_report_order = '<',
}

