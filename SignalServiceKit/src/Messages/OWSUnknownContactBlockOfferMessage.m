//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSUnknownContactBlockOfferMessage.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

// This is a deprecated class, we're keeping it around to avoid YapDB serialization errors
// TODO - remove this class, clean up existing instances, ensure any missed ones don't explode (UnknownDBObject)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation OWSUnknownContactBlockOfferMessage
#pragma clang diagnostic pop

// --- CODE GENERATION MARKER

// --- CODE GENERATION MARKER

- (BOOL)shouldUseReceiptDateForSorting
{
    // Use the timestamp, not the "received at" timestamp to sort,
    // since we're creating these interactions after the fact and back-dating them.
    return NO;
}

- (BOOL)isDynamicInteraction
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
