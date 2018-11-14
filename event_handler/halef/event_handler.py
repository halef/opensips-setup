#!/usr/bin/python2
import logging
import signal
import threading
import xmlrpclib
from logging.config import fileConfig
from os import getcwd, path
from ConfigParser import ConfigParser
from SimpleXMLRPCServer import SimpleXMLRPCServer
from SimpleXMLRPCServer import SimpleXMLRPCRequestHandler

# own dependencies
from halef.opensips import Opensips

# Set __location__ to directory of this script
__location__ = path.realpath(path.join(getcwd(), path.dirname(__file__)))

# Setup logging
fileConfig(path.join(__location__, 'logging_config.ini'), disable_existing_loggers=False)
logger = logging.getLogger(__name__)

# Load configuration
try:
    config = ConfigParser()
    config_file = path.join(__location__, 'event_handler.cfg')
    config.read(config_file)
except Exception:
    msg = "Failed to load configuration [{config}]".format(config=config_file)
    logger.exception(msg)

OPENSIPS_IP=config.get('OPENSIPS', 'IP')
OPENSIPS_XMLRPC_PATH = '/RPC2'
OPENSIPS_XMLRPC_URI = 'http://{ip}:8888'.format(ip=OPENSIPS_IP)
LISTENER_HOST = '127.0.0.1'
LISTENER_PORT = 8081
LISTENER_PATH = 'e_dummy_h'
LISTENER_URL = 'xmlrpc:{host}:{port}:{path}' .format(
    host = LISTENER_HOST,
    port = LISTENER_PORT,
    path = LISTENER_PATH
)
EVENTS = ['E_HALEF_BYE_EVENT',
          'E_HALEF_LB_FAIL_EVENT',
          'E_HALEF_RELAY_FAILED_EVENT',
          'E_HALEF_CALL_ACCEPTED_EVENT',
          'E_HALEF_CANCELLED_EVENT',
          'E_HALEF_ERROR_EVENT',
          'E_HALEF_RESTART_COMBOBOX_EVENT']

GLOBAL_TIME_TO_RESTART = None
GLOBAL_TIME_TO_DISABLE_AFTERCALL = None

# Restrict to a particular path. This is not a handler, but more of a filter
class RequestHandler(SimpleXMLRPCRequestHandler):
    rpc_paths = (OPENSIPS_XMLRPC_PATH)

def e_dummy_handler(event, name=None, value=None):
    try:    
        handler = Handler(opensips_ip=OPENSIPS_IP)
        handler.handle(event, name, value)
    except Exception as err:
        logger.exception("error in e_dummy_handler: {error}".format(str(err)))

class Handler:    
    def __init__(self,
                 db_host = config.get('DATABASE','HOST'),
                 db_name = config.get('DATABASE','DATABASE_NAME_OPENSIPS'),
                 db_user = config.get('DATABASE','USER'),
                 db_password = config.get('DATABASE','PASSWORD'),
                 opensips_ip = config.get('OPENSIPS','IP'),
                 opensips_port = config.get('OPENSIPS','PORT'),
                 logger=None):
        self.db_host = db_host
        self.db_name = db_name
        self.db_user = db_user
        self.db_password = db_password
        self.opensips_ip = opensips_ip
        self.opensips_port = opensips_port
        self.logger = logger or logging.getLogger(__name__)
        self.xmlrpc_uri = 'http://{ip}:{port}{path}'.format(
            ip=self.opensips_ip,
            port=self.opensips_port,
            path=OPENSIPS_XMLRPC_PATH
        )

    def handle(self,event, name, value):
        """ Desc: openSIPS XMLRPC event can only pass two parameters, so we will pass a 'name' and 'value'
            name - currently either 'comboBoxIP' or 'autoScaleGroup', but could be used for more in the future
            value - ip address if name parameter is 'comboBoxIP', autoScaleGroup name if 'autoScaleGroup'
        """
        try:

            self.logger.debug("event: {event} parameter 'name': {name}".format(
                event=event,
                name=name
            ))
            self.logger.debug("event: {event} parameter 'value': {vaue}".format(
                event=event,
                value=value
            ))

            if event == 'E_HALEF_BYE_EVENT':
                if name == 'comboBoxIP':
                    ip = value
                    if ip is None:
                        self.logger.error('cannot disable combobox, because ip was not sent' )
                    else:
                        self.sleep_combobox(ip, seconds=GLOBAL_TIME_TO_DISABLE_AFTERCALL)
            elif event == 'E_HALEF_LB_FAIL_EVENT' or event == 'E_HALEF_RELAY_FAILED_EVENT' or event == 'E_HALEF_CANCELLED_EVENT' or event == 'E_HALEF_ERROR_EVENT':
                pass
            elif 'E_HALEF_CALL_ACCEPTED_EVENT':
                pass
            elif event == 'E_HALEF_RESTART_COMBOBOX_EVENT':
                pass
            else:
                self.logger.error("unexpected event: {evnet}".format(event))
        except Exception:
            self.logger.exception("logger failed for event: {event}".format(event))

    def sleep_combobox(self, combobox_ip, seconds=60):
        server = Opensips(self.xmlrpc_uri)

        destination_id = server.get_id_by_ip(combobox_ip)
        
        if not destination_id:
            self.logger.error(
                "sleep could not find destination for combobox ip[{ip}".format(
                    ip=combobox_ip
                )
            )
            return

        server.disable_destination(destination_id)

        if seconds > 0:
            self.logger.debug("Sleep combobox[{ip}] for {sec} seconds.".format(
                ip=combobox_ip,
                seconds=seconds
            ))
            threading.Timer(float(seconds), self.wakeup_combobox, args=(combobox_ip))
            t.start()
        else:
            self.logger.debug("Sleep combobox[{ip}] until wake up.".format(
                ip=combobox_ip
            ))

    def wakeup_combobox(self, combobox_ip):
        server = Opensips(self.xmlrpc_uri)
        destination_id = server.get_id_by_ip(combobox_ip)
        
        if not destination_id:
            self.logger.error(
                "sleep could not find destination for combobox ip[{ip}".format(
                    ip=combobox_ip
                )
            )
            return
        
        server.enable_destination(destination_id)
        self.logger.debug("Wake up combobox[{ip}].".format(
            ip=combobox_ip
        ))

def signal_handler(signal, frame):
    try:
        exit_msg = 'Shutting down gracefully'
        logger.info(exit_msg)
        server = xmlrpclib.ServerProxy(OPENSIPS_XMLRPC_URI)        
        for event in EVENTS:
            # unsubscript from all events
            out = server.event_subscribe(event, LISTENER_URL,'0');
            logger.info("Unsubscribed from event[{event}].".format(event=event))
    except xmlrpclib.Fault as err:
        logger.exception('event error: {error}'.format(error=str(err)))
    except Exception:
        logger.exception('unknown error setting up XML-RPC server')
    finally:
        sys.exit(0)

if __name__ == "__main__":
    
    try:
        GLOBAL_TIME_TO_RESTART = config.getint(
            'TIMEOUT_SECTIONS',
            'GLOBAL_TIME_TO_RESTART_secs_int'
        )
        GLOBAL_TIME_TO_DISABLE_AFTERCALL = config.getint(
            'TIMEOUT_SECTIONS',
            'GLOBAL_TIME_TO_DISABLE_AFTERCALL_secs_int'
        )
        
        local_server = SimpleXMLRPCServer(
            (LISTENER_HOST, LISTENER_PORT),
			requestHandler=RequestHandler,
            allow_none=True
        )
        local_server.register_function(e_dummy_handler, LISTENER_PATH)
    
        signal.signal(signal.SIGINT, signal_handler)    
        signal.signal(signal.SIGTERM, signal_handler)        
         
    except xmlrpclib.Fault as err:
        logger.exception('event error: {error}'.format(error=str(err)))
    except Exception:
        logger.excpetion('unknown error setting up XML-RPC server')

    try:
        local_server.serve_forever()
    except Exception as err:
        logger.error('error STOPPED event listener server: {error}'.format(
            error=str(err))
        )
