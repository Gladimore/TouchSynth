// Minimal stand-in for Apple's headers: only what TouchSynth uses, so the sources
// can be cross-compiled and linked where no iOS SDK exists. Not for app builds.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <objc/runtime.h>

#define NS_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#define NS_ASSUME_NONNULL_END _Pragma("clang assume_nonnull end")
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NS_OPTIONS(_type, _name) enum _name : _type _name; enum _name : _type
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define NSEC_PER_SEC 1000000000ull
#define DISPATCH_TIME_NOW 0ull

typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double CGFloat;
typedef double NSTimeInterval;
typedef CGFloat UIWindowLevel;
typedef struct CGPoint { CGFloat x, y; } CGPoint;
typedef struct CGSize { CGFloat width, height; } CGSize;
typedef struct CGRect { CGPoint origin; CGSize size; } CGRect;
typedef struct UIEdgeInsets { CGFloat top, left, bottom, right; } UIEdgeInsets;
typedef NS_ENUM(NSInteger, NSComparisonResult) { NSOrderedAscending = -1, NSOrderedSame, NSOrderedDescending };
typedef NS_ENUM(NSInteger, UITouchPhase) { UITouchPhaseBegan, UITouchPhaseMoved, UITouchPhaseStationary, UITouchPhaseEnded, UITouchPhaseCancelled };
typedef NS_ENUM(NSInteger, UISceneActivationState) { UISceneActivationStateUnattached = -1, UISceneActivationStateForegroundActive, UISceneActivationStateForegroundInactive, UISceneActivationStateBackground };
typedef NS_OPTIONS(NSUInteger, UIControlEvents) { UIControlEventTouchUpInside = 1 << 6, UIControlEventValueChanged = 1 << 12, UIControlEventPrimaryActionTriggered = 1 << 13 };
typedef NS_OPTIONS(NSUInteger, UICollectionViewScrollPosition) { UICollectionViewScrollPositionNone = 0 };
typedef NS_ENUM(NSInteger, UITableViewScrollPosition) { UITableViewScrollPositionNone };

static inline CGPoint CGPointMake(CGFloat x, CGFloat y) { CGPoint p = {x, y}; return p; }
static inline bool CGPointEqualToPoint(CGPoint a, CGPoint b) { return a.x == b.x && a.y == b.y; }
static inline CGFloat CGRectGetWidth(CGRect r) { return r.size.width < 0 ? -r.size.width : r.size.width; }
static inline CGFloat CGRectGetHeight(CGRect r) { return r.size.height < 0 ? -r.size.height : r.size.height; }
extern bool CGRectContainsPoint(CGRect rect, CGPoint point);
extern const CGPoint CGPointZero;

typedef long dispatch_once_t;
typedef uint64_t dispatch_time_t;
typedef struct dispatch_queue_s *dispatch_queue_t;
extern struct dispatch_queue_s _dispatch_main_q;
#define dispatch_get_main_queue() (&_dispatch_main_q)
extern void dispatch_once(dispatch_once_t *predicate, void (^block)(void));
extern void dispatch_async(dispatch_queue_t queue, void (^block)(void));
extern void dispatch_after(dispatch_time_t when, dispatch_queue_t queue, void (^block)(void));
extern dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta);

@class NSString, NSArray, NSSet, NSBundle, NSException, NSThread, NSValue, NSNumber, NSIndexPath, NSDictionary, NSMutableDictionary;
@class UIWindow, UIView, UIEvent, UIScreen, UITouch, UIWindowScene, UIViewController, UIGestureRecognizer, UIApplication, UICollectionView, UITableView, UICollectionViewCell, UITableViewCell;

@protocol NSObject
- (BOOL)respondsToSelector:(SEL)selector;
- (NSString *)description;
@end
@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(void *)state objects:(id __unsafe_unretained _Nullable[_Nonnull])buffer count:(NSUInteger)len;
@end

__attribute__((objc_root_class))
@interface NSObject <NSObject> { Class isa; }
+ (instancetype)alloc;
- (instancetype)init;
+ (Class)class;
+ (BOOL)instancesRespondToSelector:(SEL)selector;
- (BOOL)isKindOfClass:(Class)cls;
- (id)valueForKey:(NSString *)key;
- (void)setValue:(id)value forKey:(NSString *)key;
@end

@interface NSException : NSObject @end
@interface NSString : NSObject
@property (readonly) NSUInteger length;
@property (readonly) NSString *capitalizedString;
+ (instancetype)stringWithFormat:(NSString *)format, ...;
- (BOOL)hasPrefix:(NSString *)s;
- (BOOL)containsString:(NSString *)s;
- (BOOL)isEqualToString:(NSString *)s;
@end
@interface NSValue : NSObject
@property (readonly) void *pointerValue;
@end
@interface NSNumber : NSValue
@property (readonly) double doubleValue;
+ (NSNumber *)numberWithLong:(long)v;
+ (NSNumber *)numberWithInteger:(NSInteger)v;
+ (NSNumber *)numberWithBool:(BOOL)v;
@end
@interface NSArray<ObjectType> : NSObject <NSFastEnumeration>
@property (readonly) NSUInteger count;
+ (instancetype)arrayWithObjects:(const ObjectType _Nonnull[_Nullable])objects count:(NSUInteger)count;
- (NSUInteger)indexOfObject:(ObjectType)object;
- (NSArray<ObjectType> *)sortedArrayUsingComparator:(NSComparisonResult (^)(id, id))comparator;
@end
@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
+ (instancetype)array;
- (void)addObject:(ObjectType)object;
@end
@interface NSSet<ObjectType> : NSObject
@property (readonly) NSUInteger count;
+ (instancetype)setWithObject:(ObjectType)object;
@end
@interface NSDictionary<KeyType, ObjectType> : NSObject
@property (readonly) NSArray<ObjectType> *allValues;
- (ObjectType)objectForKeyedSubscript:(KeyType)key;
@end
@interface NSMutableDictionary<KeyType, ObjectType> : NSDictionary<KeyType, ObjectType>
+ (instancetype)dictionary;
- (void)setObject:(ObjectType)object forKeyedSubscript:(KeyType)key;
- (void)removeObjectForKey:(KeyType)key;
- (void)removeAllObjects;
@end
@interface NSBundle : NSObject
@property (class, readonly) NSBundle *mainBundle;
@property (readonly) NSString *bundlePath;
+ (NSBundle *)bundleForClass:(Class)cls;
@end
@interface NSProcessInfo : NSObject
@property (class, readonly) NSProcessInfo *processInfo;
@property (readonly) NSTimeInterval systemUptime;
@end
@interface NSThread : NSObject
@property (class, readonly) BOOL isMainThread;
@end
@interface NSIndexPath : NSObject @end
extern SEL NSSelectorFromString(NSString *name);
extern NSString *NSStringFromSelector(SEL selector);
extern NSString *NSStringFromClass(Class cls);
extern void NSLog(NSString *format, ...);

@protocol UICoordinateSpace <NSObject>
- (CGPoint)convertPoint:(CGPoint)point toCoordinateSpace:(id<UICoordinateSpace>)space;
@end
@interface UIScreen : NSObject
@property (readonly) id<UICoordinateSpace> coordinateSpace;
@end
@interface UIResponder : NSObject
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
@end
@interface UIView : UIResponder <UICoordinateSpace>
@property (nonatomic, readonly) UIWindow *window;
@property (nonatomic, readonly) UIView *superview;
@property (nonatomic, readonly) NSArray<UIView *> *subviews;
@property (nonatomic, readonly) CGRect bounds;
@property (nonatomic) CGFloat alpha;
@property (nonatomic, getter=isHidden) BOOL hidden;
@property (nonatomic, getter=isUserInteractionEnabled) BOOL userInteractionEnabled;
@property (nonatomic, readonly) NSArray<UIGestureRecognizer *> *gestureRecognizers;
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
- (BOOL)isDescendantOfView:(UIView *)view;
@end
@interface UIViewController : UIResponder
@property (nonatomic, readonly) UIView *view;
@end
@interface UIWindowScene : NSObject
@property (nonatomic, readonly) UISceneActivationState activationState;
@end
@interface UIWindow : UIView
@property (nonatomic, readonly) UIWindowLevel windowLevel;
@property (nonatomic, readonly) BOOL isKeyWindow;
@property (nonatomic, readonly) UIScreen *screen;
@property (nonatomic, readonly) UIWindowScene *windowScene;
@property (nonatomic, readonly) UIViewController *rootViewController;
@property (nonatomic, readonly) id<UICoordinateSpace> coordinateSpace;
- (void)sendEvent:(UIEvent *)event;
@end
@interface UIEvent : NSObject @end
@interface UITouch : NSObject
@property (nonatomic, readonly) UIWindow *window;
@property (nonatomic, readonly) UIView *view;
@property (nonatomic, readonly) UITouchPhase phase;
- (CGPoint)locationInView:(UIView *)view;
- (CGPoint)previousLocationInView:(UIView *)view;
@end
@interface UIApplication : UIResponder
@property (class, readonly) UIApplication *sharedApplication;
@property (nonatomic, readonly) NSArray<UIWindow *> *windows __attribute__((deprecated));
- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender forEvent:(UIEvent *)event;
@end
@interface UIControl : UIView
@property (nonatomic, readonly) NSSet *allTargets;
- (void)sendActionsForControlEvents:(UIControlEvents)events;
@end
@interface UIGestureRecognizer : NSObject
@property (nonatomic, readonly) NSInteger state;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) UIView *view;
@end
@interface UITapGestureRecognizer : UIGestureRecognizer @end
@interface UIPanGestureRecognizer : UIGestureRecognizer
- (void)setTranslation:(CGPoint)translation inView:(UIView *)view;
@end
@interface UIScrollView : UIView
@property (nonatomic, readonly) CGPoint contentOffset;
@property (nonatomic, readonly) CGSize contentSize;
@property (nonatomic, readonly) UIEdgeInsets adjustedContentInset;
@property (nonatomic, getter=isScrollEnabled) BOOL scrollEnabled;
@property (nonatomic, readonly) UIPanGestureRecognizer *panGestureRecognizer;
- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated;
@end
@interface UICollectionViewCell : UIView @end
@interface UITableViewCell : UIView @end
@protocol UICollectionViewDelegate <NSObject>
@optional
- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)path;
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)path;
@end
@protocol UITableViewDelegate <NSObject>
@optional
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path;
@end
@interface UICollectionView : UIScrollView
@property (nonatomic, readonly) id<UICollectionViewDelegate> delegate;
@property (nonatomic, readonly) BOOL allowsSelection;
- (NSIndexPath *)indexPathForCell:(UICollectionViewCell *)cell;
- (void)selectItemAtIndexPath:(NSIndexPath *)path animated:(BOOL)animated scrollPosition:(UICollectionViewScrollPosition)position;
@end
@interface UITableView : UIScrollView
@property (nonatomic, readonly) id<UITableViewDelegate> delegate;
@property (nonatomic, readonly) BOOL allowsSelection;
- (NSIndexPath *)indexPathForCell:(UITableViewCell *)cell;
- (void)selectRowAtIndexPath:(NSIndexPath *)path animated:(BOOL)animated scrollPosition:(UITableViewScrollPosition)position;
@end
