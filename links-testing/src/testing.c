#include <openssl/is_awslc.h>
#include <openssl/evp.h>
#include <openssl/x509.h>

int testing_evp_key_type(int nid) {
    // X509_free is outside the universal bindings, so this links only if the
    // default build keeps all of libcrypto, as C code like s2n-tls's needs.
    X509_free(NULL);
    return EVP_PKEY_type(nid);
}
