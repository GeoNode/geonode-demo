import logging

logger = logging.getLogger(__name__)

USERNAMES = [
    'Jam_1998',
    'cbms_mapping',
    'g',
]

FILENAMES = [
    'burgos',
    'limasawa',
    'points',
]

class LogRequestMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response
        # One-time configuration and initialization.

    def __call__(self, request):
        self.log_actions(request)
        response = self.get_response(request)
        return response
    
    def log_actions(self, request):
        self._log_dataset_upload(request)
        self._log_signup(request)
        self._log_signin(request)
        self._log_email_confirm(request)
            
    def log(self, request, msg):
        client_ip = request.META['REMOTE_ADDR']
        referer = request.headers['Referer']
        agent = request.headers['User-Agent']
        logger.info(f'LogRequestMiddleware - {msg} (IP: {client_ip}, Referer: {referer}, Agemt {agent})')

    def _log_signup(self, request):
        if '/account/signup/' in request.path and request.method == "POST":
            try:
                username = request.POST['username']
                if not self._filter_username(username):
                    return
                email = request.POST['email']
                self.log(request, f'Signup from {username} - {email}')
            except:
                self.log(request, f'Signup without username')
                
    def _log_signin(self, request):
        if '/account/login' in request.path and request.method == "POST":
            try:
                username = request.POST['login']
                if not self._filter_username(username):
                    return
                self.log(request, f'Login from {username}')
            except:
                self.log(request, f'Signup without username')
        
    def _log_email_confirm(self, request):
        if '/account/confirm' in request.path:
            self.log(request, f'Email confirm with {request.path}')
            
        
    def _log_dataset_upload(self, request):
        if '/api/v2/uploads/upload' in request.path:
            base_file = request.FILES.get("base_file", None)
            if base_file:
                if not self._filter_files(base_file.name):
                    return
                self.log(request, f'Uploading {base_file.name}')
                
    def _filter_username(self, username):
        return any(needle in username.lower() for needle in USERNAMES)
    
    def _filter_files(self, filename):
        return any(needle in filename.lower() for needle in FILENAMES)