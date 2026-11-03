#import <Cocoa/Cocoa.h>
int main(int argc,char **argv) {
  @autoreleasepool {
    NSImage *image=[[NSImage alloc] initWithSize:NSMakeSize(1024,1024)]; [image lockFocus];
    NSBezierPath *tile=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(40,40,944,944) xRadius:215 yRadius:215];
    NSGradient *gradient=[[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:.58 green:.65 blue:.86 alpha:1] endingColor:[NSColor colorWithSRGBRed:.30 green:.33 blue:.62 alpha:1]];
    [gradient drawInBezierPath:tile angle:65];
    [[NSColor colorWithWhite:1 alpha:.92] setStroke];
    NSBezierPath *circle=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(247,247,530,530)]; circle.lineWidth=24; [circle stroke];
    NSAffineTransform *transform=[NSAffineTransform transform]; [transform translateXBy:512 yBy:512]; [transform rotateByDegrees:35];
    NSBezierPath *orbit=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(-360,-172,720,344)]; [orbit transformUsingAffineTransform:transform]; orbit.lineWidth=21; [orbit stroke];
    [[NSColor whiteColor] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(697,684,66,66)] fill];
    [image unlockFocus]; NSBitmapImageRep *bitmap=[NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
    NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES]?0:1;
  }
}
