//
//  launchctl_lite.c
//  Package Uninstaller
//
//  Created by hewig on 9/6/13.
//  Copyright (c) 2013 hewig. All rights reserved.
//

#include "launchctl_lite.h"

static void _launch_data_iterate(launch_data_t obj, const char *key, CFMutableDictionaryRef dict);
static mach_port_t str2bsport(const char *s);
static CFDictionaryRef CFDictionaryCreateFromLaunchDictionary(launch_data_t dict);
static CFTypeRef CFTypeCreateFromLaunchData(launch_data_t obj);
static CFArrayRef CFArrayCreateFromLaunchArray(launch_data_t arr);
bool launch_data_array_append(launch_data_t a, launch_data_t o);
void launchctl_log(int level, const char *fmt, ...);
void launchctl_log_CFString(int level, CFStringRef string);
void print_obj(launch_data_t obj, const char *key, void *context __attribute__((unused)));
void print_jobs(launch_data_t j, const char *key __attribute__((unused)), void *context __attribute__((unused)));

#define LAUNCH_ENV_KEEPCONTEXT	"LaunchKeepContext"

void
launchctl_setup_system_context(void)
{
	if (getenv(LAUNCHD_SOCKET_ENV)) {
		return;
	}
    
	if (getenv(LAUNCH_ENV_KEEPCONTEXT)) {
		return;
	}
    
	if (geteuid() != 0) {
		launchctl_log(LOG_ERR, "You must be the root user to perform this operation.");
		return;
	}
    
	/* Use the system launchd's socket. */
	setenv("__USE_SYSTEM_LAUNCHD", "1", 0);
    
	/* Put ourselves in the system launchd's bootstrap. */
	mach_port_t rootbs = str2bsport("/");
	mach_port_deallocate(mach_task_self(), bootstrap_port);
	task_set_bootstrap_port(mach_task_self(), rootbs);
	bootstrap_port = rootbs;
}

mach_port_t
str2bsport(const char *s)
{
	bool getrootbs = strcmp(s, "/") == 0;
	mach_port_t last_bport, bport = bootstrap_port;
	task_t task = mach_task_self();
	kern_return_t result;
    
	if (strcmp(s, "..") == 0 || getrootbs) {
		do {
			last_bport = bport;
			result = bootstrap_parent(last_bport, &bport);
            
			if (result == BOOTSTRAP_NOT_PRIVILEGED) {
				launchctl_log(LOG_ERR, "Permission denied");
				return 1;
			} else if (result != BOOTSTRAP_SUCCESS) {
				launchctl_log(LOG_ERR, "bootstrap_parent() %d", result);
				return 1;
			}
		} while (getrootbs && last_bport != bport);
	} else if (strcmp(s, "0") == 0 || strcmp(s, "NULL") == 0) {
		bport = MACH_PORT_NULL;
	} else {
		int pid = atoi(s);
        
		result = task_for_pid(mach_task_self(), pid, &task);
        
		if (result != KERN_SUCCESS) {
			launchctl_log(LOG_ERR, "task_for_pid() %s", mach_error_string(result));
			return 1;
		}
        
		result = task_get_bootstrap_port(task, &bport);
        
		if (result != KERN_SUCCESS) {
			launchctl_log(LOG_ERR, "Couldn't get bootstrap port: %s", mach_error_string(result));
			return 1;
		}
	}
    
	return bport;
}

void
launchctl_log(int level, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
    
    char *buff = NULL;
    (void)vasprintf(&buff, fmt, ap);
    
    FILE *where = stdout;
    if (level < LOG_NOTICE) {
        where = stderr;
    }
    
    fprintf(where, "%s\n", buff);
    free(buff);
    
	va_end(ap);
}

void
launchctl_log_CFString(int level, CFStringRef string)
{
	// Big enough. Don't feel like jumping through CF's hoops.
	char *buff = malloc(4096);
	(void)CFStringGetCString(string, buff, 4096, kCFStringEncodingUTF8);
	launchctl_log(level, "%s", buff);
	free(buff);
}

void
print_obj(launch_data_t obj, const char *key, void *context __attribute__((unused)))
{
	static size_t indent = 0;
	size_t i, c;
    
	for (i = 0; i < indent; i++) {
		fprintf(stdout, "\t");
	}
    
	if (key) {
		fprintf(stdout, "\"%s\" = ", key);
	}
    
	switch (launch_data_get_type(obj)) {
        case LAUNCH_DATA_STRING:
            fprintf(stdout, "\"%s\";\n", launch_data_get_string(obj));
            break;
        case LAUNCH_DATA_INTEGER:
            fprintf(stdout, "%lld;\n", launch_data_get_integer(obj));
            break;
        case LAUNCH_DATA_REAL:
            fprintf(stdout, "%f;\n", launch_data_get_real(obj));
            break;
        case LAUNCH_DATA_BOOL:
            fprintf(stdout, "%s;\n", launch_data_get_bool(obj) ? "true" : "false");
            break;
        case LAUNCH_DATA_ARRAY:
            c = launch_data_array_get_count(obj);
            fprintf(stdout, "(\n");
            indent++;
            for (i = 0; i < c; i++) {
                print_obj(launch_data_array_get_index(obj, i), NULL, NULL);
            }
            indent--;
            for (i = 0; i < indent; i++) {
                fprintf(stdout, "\t");
            }
            fprintf(stdout, ");\n");
            break;
        case LAUNCH_DATA_DICTIONARY:
            fprintf(stdout, "{\n");
            indent++;
            launch_data_dict_iterate(obj, print_obj, NULL);
            indent--;
            for (i = 0; i < indent; i++) {
                fprintf(stdout, "\t");
            }
            fprintf(stdout, "};\n");
            break;
        case LAUNCH_DATA_FD:
            fprintf(stdout, "file-descriptor-object;\n");
            break;
        case LAUNCH_DATA_MACHPORT:
            fprintf(stdout, "mach-port-object;\n");
            break;
        default:
            fprintf(stdout, "???;\n");
            break;
	}
}

void
print_jobs(launch_data_t j, const char *key __attribute__((unused)), void *context __attribute__((unused)))
{
	static size_t depth = 0;
	launch_data_t lo = launch_data_dict_lookup(j, LAUNCH_JOBKEY_LABEL);
	launch_data_t pido = launch_data_dict_lookup(j, LAUNCH_JOBKEY_PID);
	launch_data_t stato = launch_data_dict_lookup(j, LAUNCH_JOBKEY_LASTEXITSTATUS);
	const char *label = launch_data_get_string(lo);
	size_t i;
    
	if (pido) {
		fprintf(stdout, "%lld\t-\t%s\n", launch_data_get_integer(pido), label);
	} else if (stato) {
		int wstatus = (int)launch_data_get_integer(stato);
		if (WIFEXITED(wstatus)) {
			fprintf(stdout, "-\t%d\t%s\n", WEXITSTATUS(wstatus), label);
		} else if (WIFSIGNALED(wstatus)) {
			fprintf(stdout, "-\t-%d\t%s\n", WTERMSIG(wstatus), label);
		} else {
			fprintf(stdout, "-\t???\t%s\n", label);
		}
	} else {
		fprintf(stdout, "-\t-\t%s\n", label);
	}
	for (i = 0; i < depth; i++) {
		fprintf(stdout, "\t");
	}
}

bool
launch_data_array_append(launch_data_t a, launch_data_t o)
{
	size_t offt = launch_data_array_get_count(a);
    
	return launch_data_array_set_index(a, o, offt);
}

bool launchctl_is_job_alive(const char* label)
{
    bool alive = false;
    
    if (!label) {
        return alive;
    }
    
    launch_data_t resp, msg = NULL;
    
    msg = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
    launch_data_dict_insert(msg, launch_data_new_string(label), LAUNCH_KEY_GETJOB);
    
    resp = launch_msg(msg);
    launch_data_free(msg);
    
    if (resp == NULL) {
        alive = false;
    } else {
        if (launch_data_get_type(resp) != LAUNCH_DATA_DICTIONARY){
            alive = false;
        } else {
            launch_data_t pid = launch_data_dict_lookup(resp, LAUNCH_JOBKEY_PID);
            launch_data_t status = launch_data_dict_lookup(resp, LAUNCH_JOBKEY_LASTEXITSTATUS);
            if (pid && launch_data_get_integer(pid) > 0) {
                printf("%s pid is %lld\n", label, launch_data_get_integer(pid));
                alive = true;
            } else if (status){
                //some schedule/watch task is another kind of alive
                long exit_status = launch_data_get_integer(status);
                if(WEXITSTATUS(exit_status) == EXIT_SUCCESS){
                    alive = true;
                } else {
                    alive = false;
                }
            } else {
               alive = false; 
            }
        }
        launch_data_free(resp);
    }
    
    return alive;
}

int
launchctl_list_cmd(const char* label)
{
	launch_data_t resp, msg = NULL;
	int r = 0;
    
	bool plist_output = false;
	
	if (label) {
		msg = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
		launch_data_dict_insert(msg, launch_data_new_string(label), LAUNCH_KEY_GETJOB);
        
		resp = launch_msg(msg);
		launch_data_free(msg);
        
		if (resp == NULL) {
			launchctl_log(LOG_ERR, "launch_msg(): %s", strerror(errno));
			r = 1;
		} else if (launch_data_get_type(resp) == LAUNCH_DATA_DICTIONARY) {
			if (plist_output) {
				CFDictionaryRef respDict = CFDictionaryCreateFromLaunchDictionary(resp);
				CFStringRef plistStr = NULL;
				if (respDict) {
					CFDataRef plistData = CFPropertyListCreateXMLData(NULL, (CFPropertyListRef)respDict);
					CFRelease(respDict);
					if (plistData) {
						plistStr = CFStringCreateWithBytes(NULL, CFDataGetBytePtr(plistData), CFDataGetLength(plistData), kCFStringEncodingUTF8, false);
						CFRelease(plistData);
					} else {
						r = 1;
					}
				} else {
					r = 1;
				}
                
				if (plistStr) {
					launchctl_log_CFString(LOG_NOTICE, plistStr);
					CFRelease(plistStr);
					r = 0;
				}
			} else {
				print_obj(resp, NULL, NULL);
				r = 0;
			}
			launch_data_free(resp);
		} else {
			//launchctl_log(LOG_ERR, "%s %s returned unknown response", getprogname(), argv[0]);
			r = 1;
			launch_data_free(resp);
		}
	} else if (vproc_swap_complex(NULL, VPROC_GSK_ALLJOBS, NULL, &resp) == NULL) {
		fprintf(stdout, "PID\tStatus\tLabel\n");
		launch_data_dict_iterate(resp, print_jobs, NULL);
		launch_data_free(resp);
        
		r = 0;
	}
    
	return r;
}

int
launchctl_submit_cmd(const char* label, const char* executable, const char* stdout_path, const char* stderr_path, const char* argv[])
{
	launch_data_t msg = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
	launch_data_t job = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
	launch_data_t resp, largv = launch_data_alloc(LAUNCH_DATA_ARRAY);
	int rc = 0;
    
	launch_data_dict_insert(job, launch_data_new_bool(false), LAUNCH_JOBKEY_ONDEMAND);
    
    launch_data_dict_insert(job, launch_data_new_string(label), LAUNCH_JOBKEY_LABEL);
    launch_data_dict_insert(job, launch_data_new_string(executable), LAUNCH_JOBKEY_PROGRAM);
    launch_data_dict_insert(job, launch_data_new_string(stdout_path), LAUNCH_JOBKEY_STANDARDOUTPATH);
    launch_data_dict_insert(job, launch_data_new_string(stderr_path), LAUNCH_JOBKEY_STANDARDERRORPATH);

	if (argv) {
        for (int i = 0; argv[0]; i++) {
            launch_data_array_append(largv, launch_data_new_string(argv[i]));
        }
    }
    
	launch_data_dict_insert(job, largv, LAUNCH_JOBKEY_PROGRAMARGUMENTS);
	launch_data_dict_insert(msg, job, LAUNCH_KEY_SUBMITJOB);
    
	resp = launch_msg(msg);
	launch_data_free(msg);
    
	if (resp == NULL) {
		launchctl_log(LOG_ERR, "launch_msg(): %s", strerror(errno));
		return 1;
	} else if (launch_data_get_type(resp) == LAUNCH_DATA_ERRNO) {
		errno = launch_data_get_errno(resp);
		if (errno) {
			launchctl_log(LOG_ERR, "%s %s error: %s", getprogname(), executable, strerror(errno));
			rc = 1;
		}
	} else {
		launchctl_log(LOG_ERR, "%s %s error: %s", getprogname(), executable, "unknown response");
	}
    
	launch_data_free(resp);
    
	return rc;
}

int
launchctl_remove_cmd(const char* label){
    launch_data_t resp, msg;
    const char *lmsgcmd = LAUNCH_KEY_REMOVEJOB;
    int e, r = 0;

    msg = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
    launch_data_dict_insert(msg, launch_data_new_string(label), lmsgcmd);
    
    resp = launch_msg(msg);
    launch_data_free(msg);
    
    if (resp == NULL) {
        launchctl_log(LOG_ERR, "launch_msg(): %s", strerror(errno));
        return 1;
    } else if (launch_data_get_type(resp) == LAUNCH_DATA_ERRNO) {
        if ((e = launch_data_get_errno(resp))) {
            launchctl_log(LOG_ERR, "%s %s error: %s", getprogname(), label, strerror(e));
            r = 1;
        }
    } else {
        launchctl_log(LOG_ERR, "%s %s returned unknown response", getprogname(), label);
        r = 1;
    }
    
    launch_data_free(resp);
    return r;
}

static inline Boolean
_is_launch_data_t(launch_data_t obj)
{
	Boolean result = true;
    
	switch (launch_data_get_type(obj)) {
		case LAUNCH_DATA_STRING		: break;
		case LAUNCH_DATA_INTEGER	: break;
		case LAUNCH_DATA_REAL		: break;
		case LAUNCH_DATA_BOOL		: break;
		case LAUNCH_DATA_ARRAY		: break;
		case LAUNCH_DATA_DICTIONARY	: break;
		case LAUNCH_DATA_FD 		: break;
		case LAUNCH_DATA_MACHPORT	: break;
		default						: result = false;
	}
    
	return result;
}

static void
_launch_data_iterate(launch_data_t obj, const char *key, CFMutableDictionaryRef dict)
{
	if (obj && _is_launch_data_t(obj)) {
		CFStringRef cfKey = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
		CFTypeRef cfVal = CFTypeCreateFromLaunchData(obj);
        
		if (cfVal) {
			CFDictionarySetValue(dict, cfKey, cfVal);
			CFRelease(cfVal);
		}
		CFRelease(cfKey);
	}
}

#pragma mark CFDictionary / CFPropertyList
static CFDictionaryRef
CFDictionaryCreateFromLaunchDictionary(launch_data_t dict)
{
	CFDictionaryRef result = NULL;
    
	if (launch_data_get_type(dict) == LAUNCH_DATA_DICTIONARY) {
		CFMutableDictionaryRef mutResult = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
		launch_data_dict_iterate(dict, (void (*)(launch_data_t, const char *, void *))_launch_data_iterate, mutResult);
        
		result = CFDictionaryCreateCopy(NULL, mutResult);
		CFRelease(mutResult);
	}
    
	return result;
}

static CFTypeRef
CFTypeCreateFromLaunchData(launch_data_t obj)
{
	CFTypeRef cfObj = NULL;
    
	switch (launch_data_get_type(obj)) {
        case LAUNCH_DATA_STRING: {
            const char *str = launch_data_get_string(obj);
            cfObj = CFStringCreateWithCString(NULL, str, kCFStringEncodingUTF8);
            break;
        }
        case LAUNCH_DATA_INTEGER: {
            long long integer = launch_data_get_integer(obj);
            cfObj = CFNumberCreate(NULL, kCFNumberLongLongType, &integer);
            break;
        }
        case LAUNCH_DATA_REAL: {
            double real = launch_data_get_real(obj);
            cfObj = CFNumberCreate(NULL, kCFNumberDoubleType, &real);
            break;
        }
        case LAUNCH_DATA_BOOL: {
            bool yesno = launch_data_get_bool(obj);
            cfObj = yesno ? kCFBooleanTrue : kCFBooleanFalse;
            break;
        }
        case LAUNCH_DATA_ARRAY: {
            cfObj = (CFTypeRef)CFArrayCreateFromLaunchArray(obj);
            break;
        }
        case LAUNCH_DATA_DICTIONARY: {
            cfObj = (CFTypeRef)CFDictionaryCreateFromLaunchDictionary(obj);
            break;
        }
        case LAUNCH_DATA_FD: {
            int fd = launch_data_get_fd(obj);
            cfObj = CFNumberCreate(NULL, kCFNumberIntType, &fd);
            break;
        }
        case LAUNCH_DATA_MACHPORT: {
            mach_port_t port = launch_data_get_machport(obj);
            cfObj = CFNumberCreate(NULL, kCFNumberIntType, &port);
            break;
        }
        default:
            break;
	}
    
	return cfObj;
}

#pragma mark CFArray
static CFArrayRef
CFArrayCreateFromLaunchArray(launch_data_t arr)
{
	CFArrayRef result = NULL;
	CFMutableArrayRef mutResult = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    
	if (launch_data_get_type(arr) == LAUNCH_DATA_ARRAY) {
		unsigned long count = launch_data_array_get_count(arr);
		unsigned int i = 0;
        
		for (i = 0; i < count; i++) {
			launch_data_t launch_obj = launch_data_array_get_index(arr, i);
			CFTypeRef obj = CFTypeCreateFromLaunchData(launch_obj);
            
			if (obj) {
				CFArrayAppendValue(mutResult, obj);
				CFRelease(obj);
			}
		}
        
		result = CFArrayCreateCopy(NULL, mutResult);
	}
    
	if (mutResult) {
		CFRelease(mutResult);
	}
	return result;
}