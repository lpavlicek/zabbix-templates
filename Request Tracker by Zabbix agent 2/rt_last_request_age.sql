SELECT TIMESTAMPDIFF(SECOND, Created, NOW()) AS age_seconds FROM rt6.Transactions WHERE Type IN ('Create','Correspond') ORDER BY id DESC LIMIT 1
