# Generated proxy environment exports (bash-tpl template)

% if [[ -n ${MY_PROXY_URL:-} ]]; then
export MY_PROXY_URL=<%|%q|${MY_PROXY_URL}%>
% fi

% if [[ -n ${MY_NO_PROXY_STR:-} ]]; then
export MY_NO_PROXY_STR=<%|%q|${MY_NO_PROXY_STR}%>
% fi

% if [[ -n ${MY_USE_MITM_INTERCEPT_PROXY_CERT:-} ]]; then
export MY_USE_MITM_INTERCEPT_PROXY_CERT=<%|%q|${MY_USE_MITM_INTERCEPT_PROXY_CERT}%>
% fi

% if [[ -n ${MY_DISABLE_IPV6_BOOL:-} ]]; then
export MY_DISABLE_IPV6_BOOL=<%|%q|${MY_DISABLE_IPV6_BOOL}%>
% fi

