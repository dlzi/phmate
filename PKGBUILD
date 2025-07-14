# Maintainer: Daniel Zilli
pkgname=phmate
pkgver=1.1.0
pkgrel=1
pkgdesc="A lightweight tool to manage PHP's built-in web server for local development."
arch=('any')
url="https://github.com/dlzi/phmate"
license=('MIT')
depends=('bash>=4.4' 'php>=8.0.0')
optdepends=(
    'bash-completion: for command-line completion'
    'lsof: for better process and port management'
    'ss: alternative tool for port checking'
)
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP') # Replace 'SKIP' with the actual sha256 checksum

package() {
    cd "$srcdir/$pkgname-$pkgver"
    # Install main script
    install -Dm755 src/phmate.sh "$pkgdir/usr/bin/phmate"
    # Install documentation
    install -d "$pkgdir/usr/share/doc/phmate"
    install -Dm644 README.md "$pkgdir/usr/share/doc/phmate/"
    install -Dm644 CHANGELOG.md "$pkgdir/usr/share/doc/phmate/"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    # Install man page
    install -Dm644 docs/man/phmate.1 "$pkgdir/usr/share/man/man1/phmate.1"
    # Install bash completion
    install -Dm644 completion/bash/phmate "$pkgdir/usr/share/bash-completion/completions/phmate"
}
