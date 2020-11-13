// This script determines whether and how we monetize.

var enableAds = false;

function showAds () {
    // show cookie banner, hidden by default
    try {
        document.getElementById('cookies')
            .style
            .visibility = 'visible';
    } catch (error) {
        console.error('Cannot show cookie banner:', error);
    }
}

if (enableAds) {
    showAds()
}
