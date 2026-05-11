(use-modules (guix packages)
             (gnu packages guile)
             (gnu packages guile-xyz)
             (gnu packages tls)
             (gnu packages certs)
             (gnu packages nss)
             (gnu packages texinfo)
             (gnu packages compression)
             (gnu packages rust)
             (gnu packages version-control)
             (gnu packages base))

(packages->manifest
 (list guile-3.0
       guile-json-4
       guile-gnutls
       guile-fibers
       rust
       nss-certs
       coreutils
       git
       texinfo
       gzip))
