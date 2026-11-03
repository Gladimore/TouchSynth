#pragma once
#include <stddef.h>
#include <stdbool.h>

typedef bool BOOL;
#define YES __objc_yes
#define NO __objc_no
#define nil ((id)0)
#define __unused __attribute__((unused))

typedef struct objc_ivar *Ivar;
typedef struct objc_method *Method;
typedef void (*IMP)(void);
#define Nil ((Class)0)
enum { OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1 };

extern Class object_getClass(id object);
extern Ivar class_getInstanceVariable(Class cls, const char *name);
extern ptrdiff_t ivar_getOffset(Ivar ivar);
extern const char *ivar_getTypeEncoding(Ivar ivar);
extern void object_setIvar(id object, Ivar ivar, id value);
extern id object_getIvar(id object, Ivar ivar);
extern Method class_getInstanceMethod(Class cls, SEL selector);
extern IMP method_setImplementation(Method method, IMP imp);
extern BOOL class_respondsToSelector(Class cls, SEL selector);
extern Class objc_getClass(const char *name);
extern id objc_getAssociatedObject(id object, const void *key);
extern void objc_setAssociatedObject(id object, const void *key, id value, unsigned long policy);
