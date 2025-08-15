Kontrola, zda není otevřen nešifrovaný LDAP port - po instalaci slapd je automaticky otevřen.

Nahrajte šablonu a přiřaďte k hostu, který chcete kontrolovat - musí mít nakonfigurovaný interface. Pro kontrolu se používá _Simple check_, `net.tcp.service[ldap,,]`.
Je definován jeden trigger, defaultně se testuje každou minutu.

