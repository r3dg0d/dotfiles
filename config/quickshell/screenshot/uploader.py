"""Private guns.lol uploader configuration imported from the account dashboard."""
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlparse, urlencode
from urllib.request import Request, urlopen
import subprocess


def config_path():
    return Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'galaxyshot/uploader.json'


def validate(config):
    endpoint = urlparse(config.get('RequestURL', ''))
    if endpoint.scheme != 'https' or not endpoint.hostname or endpoint.username or endpoint.password:
        raise ValueError('Uploader must specify an HTTPS RequestURL')
    if config.get('RequestMethod', 'POST').upper() != 'POST':
        raise ValueError('Only POST uploader configurations are supported')
    if config.get('Body', 'MultipartFormData') != 'MultipartFormData':
        raise ValueError('Only multipart uploader configurations are supported')
    selector = config.get('URL', '{json:url}')
    # ShareX exports both legacy $json:path$ and current {json:path} syntax.
    if re.fullmatch(r'\$json:[\w.]+\$', selector):
        selector = '{' + selector[1:-1] + '}'
        config['URL'] = selector
    if not re.fullmatch(r'\{json:[\w.]+\}', selector):
        raise ValueError('Unsupported share-link selector; expected {json:url} or {json:data.url}')
    return config


def import_config(filename):
    source = Path(filename.removeprefix('file://')).expanduser()
    data = validate(json.loads(source.read_text()))
    target = config_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    # Do not put the upload key in git, logs, or a command argument.
    temporary = target.with_suffix('.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, 'w') as file:
        json.dump(data, file)
    temporary.replace(target)


def upload(path):
    if not config_path().exists():
        raise ValueError('Import your guns.lol dashboard uploader config first')
    config = validate(json.loads(config_path().read_text()))
    endpoint = config['RequestURL']
    if config.get('Parameters'):
        endpoint += ('&' if '?' in endpoint else '?') + urlencode(config['Parameters'])
    # Credentials go through stdin, never process arguments or diagnostic output.
    options = [('url', endpoint), ('user-agent', 'GalaxyShot/0.1'), ('header', 'Accept: application/json')]
    for key, value in (config.get('Headers') or {}).items():
        options.append(('header', str(key) + ': ' + str(value)))
    for key, value in (config.get('Arguments') or {}).items():
        options.append(('form-string', str(key) + '=' + str(value)))
    field = str(config.get('FileFormName', 'file'))
    if not re.fullmatch(r'[\w.-]+', field):
        raise ValueError('Invalid upload file field')
    filename = str(Path(path).resolve())
    if any(c in filename for c in ('"', '\r', '\n')):
        raise ValueError('Unsupported screenshot filename')
    options.append(('form', field + '=@"' + filename + '";type=image/png'))
    settings = '\n'.join(key + ' = ' + json.dumps(value) for key, value in options) + '\n'
    try:
        response = subprocess.run(['curl', '--disable', '--config', '-', '--silent', '--show-error',
            '--proto', '=https', '--connect-timeout', '10', '--max-time', '45',
            '--write-out', '\n%{http_code}'], input=settings, text=True,
            capture_output=True, timeout=50)
    except subprocess.TimeoutExpired:
        raise ValueError('guns.lol upload timed out; try again') from None
    except OSError:
        raise ValueError('curl is unavailable; install curl to upload') from None
    if response.returncode:
        reasons = {5: 'proxy lookup failed', 6: 'DNS lookup failed', 7: 'connection failed',
                   28: 'connection timed out', 35: 'TLS connection failed',
                   60: 'TLS certificate validation failed; check system certificates'}
        raise ValueError('guns.lol: ' + reasons.get(response.returncode, f'network failure (curl {response.returncode})'))
    body, _, status = response.stdout.rpartition('\n')
    try:
        result = json.loads(body)
    except ValueError:
        raise ValueError(f'guns.lol returned HTTP {status} without JSON; the request may be blocked') from None
    error = result.get('error') or result.get('message') if isinstance(result, dict) else None
    if not status.startswith('2') or (isinstance(result, dict) and result.get('error')):
        detail = str(error) if isinstance(error, (str, int)) else 'Upload rejected'
        # Servers can echo a submitted key. Never expose it in the editor.
        for group in ('Arguments', 'Headers', 'Parameters'):
            for secret in (config.get(group) or {}).values():
                if len(str(secret)) >= 4:
                    detail = detail.replace(str(secret), '[redacted]')
        detail = re.sub(r'[\r\n]+', ' ', detail)[:180]
        raise ValueError(f'guns.lol HTTP {status}: {detail}')
    selector = config.get('URL', '{json:url}')[6:-1]
    for key in selector.split('.'):
        result = result.get(key) if isinstance(result, dict) else None
    if not isinstance(result, str) or urlparse(result).scheme not in ('http', 'https') or not urlparse(result).hostname:
        raise ValueError('Upload returned no valid share link')
    return result


if __name__ == '__main__':
    try:
        import_config(sys.argv[1])
        print(json.dumps({'message': 'guns.lol uploader imported · ready to upload'}))
    except Exception:
        print(json.dumps({'message': 'Could not import uploader. Choose a current JSON/SXCU config from the guns.lol dashboard.'}))
