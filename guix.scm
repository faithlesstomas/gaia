(use-modules (guix packages)
             (gnu packages guile)
             (gnu packages guile-xyz)
             (gnu packages tls)
             (gnu packages certs)
             (gnu packages nss)
             (gnu packages texinfo)
             (gnu packages base))

(packages->manifest
 (list guile-3.0
       guile-json-4
       guile-gnutls
       nss-certs
       coreutils
       texinfo))
